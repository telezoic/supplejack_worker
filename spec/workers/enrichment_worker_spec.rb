require "spec_helper"

describe EnrichmentWorker do

  class TestClass
    class_attribute :environment
    def self.get_source_id; "nlnzcat"; end
  end

  let(:worker) { EnrichmentWorker.new }
  let(:job) { FactoryGirl.create(:enrichment_job, environment: "production", enrichment: "ndha_rights") }
  let(:parser) { mock(:parser, enrichment_definitions: {ndha_rights: {type: "TapuhiRecords"}}, loader: mock(:loader, parser_class: TestClass)).as_null_object }

  before(:each) do
    job.stub(:parser) { parser }
    worker.stub(:job) { job }
    worker.stub(:api_update_finished?) { true }
  end

  describe "#perform" do

    it "should set the @job_id" do
      worker.perform(1234)
      worker.instance_variable_get("@job_id").should eq 1234
    end

    it "should mark the job as started" do
      job.should_receive(:start!)
      worker.perform(1234)
    end

    it "should setup the parser" do
      worker.stub(:records) { [] }
      worker.should_receive(:setup_parser).and_call_original
      worker.perform(1234)
    end

    it "should process every record" do
      record = mock(:record)
      worker.stub(:records) { [record] }
      worker.should_receive(:process_record).with(record)
      worker.perform(1234)
    end

    it "should finish the enrichment_job" do
      job.should_receive(:finish!)
      worker.perform(1234)
    end

    it "stops processing the records" do
      worker.stub(:stop_harvest?) { true }
      worker.should_not_receive(:process_record)
      worker.perform(1)
    end

    it "should check the api update has finished" do
      worker.should_receive(:api_update_finished?)
      worker.perform(1)
    end

    it "should call before and after on the Enrichment class" do
      HarvesterCore::TapuhiRecordsEnrichment.should_receive(:before).with("ndha_rights")
      HarvesterCore::TapuhiRecordsEnrichment.should_receive(:after).with("ndha_rights")
      worker.perform(1)
    end
  end

  describe "#records" do

    let(:query) { mock(:query).as_null_object }

    before(:each) do
      worker.send(:setup_parser)
      TestClass.stub(:get_source_id) { "nlnzcat" }
    end

    it "should fetch records based on the source_id" do
      Repository::Record.should_receive(:where).with("sources.source_id" => "nlnzcat") { query }
      worker.records
    end

    context "record_id is set" do
      before { job.stub(:record_id) {"abc123"} }

      it "should fetch a specific record" do
        Repository::Record.should_receive(:where).with(record_id: job.record_id, "sources.source_id" => "nlnzcat") { query }
        worker.records
      end

      context "preview environment" do

        before { job.stub(:preview?) { true } }

        it "should fetch a specific record from the preview_records collection" do
          Repository::PreviewRecord.should_receive(:where).and_call_original
          worker.records
        end
      end
    end
  end

  describe "#process_record" do
    let(:record) { mock(:record).as_null_object }
    let(:enrichment) { mock(:enrichment, errors: []).as_null_object }

    before do
      worker.send(:setup_parser)
      parser.stub(:enrichment_definitions) { {ndha_rights: {}} }
      HarvesterCore::Enrichment.stub(:new) { enrichment }
      worker.stub(:post_to_api) { nil }
    end

    it "should initialize a enrichment" do
      HarvesterCore::Enrichment.should_receive(:new).with("ndha_rights", worker.send(:enrichment_options), record, TestClass)
      worker.process_record(record)
    end

    it "should call increment_processed_count!" do
      worker.stub(:enrichment_job) { job }
      job.should_receive(:increment_processed_count!)
      worker.process_record(record)
    end

    context "enrichable" do

      before { enrichment.stub(:enrichable?) { true } }

      it "should set the enrichment attributes" do
        enrichment.should_receive(:set_attribute_values)
        worker.process_record(record)
      end

      it "should post to the api" do
        worker.should_receive(:post_to_api).with(enrichment)
        worker.process_record(record)
      end

      it "should post to the api in a test environment" do
        job.stub(:test?) { true }
        worker.should_not_receive(:post_to_api).with(enrichment)
        worker.process_record(record)
      end

      it "should rescue from a exception in processing the record" do
        enrichment.stub(:set_attribute_values).and_raise(StandardError.new("Hi"))
        worker.process_record(record)
      end
    end

    context "not enrichable" do

      before { enrichment.stub(:enrichable?) { false } }

      it "should not set the enrichment attributes" do
        enrichment.should_not_receive(:set_attribute_values)
        worker.process_record(record)
      end

      it "should not post to the api" do
        worker.should_not_receive(:post_to_api).with(enrichment)
        worker.process_record(record)
      end

      it "should not increment the records count on the job" do
        job.should_not_receive(:increment_records_count!)
        worker.process_record(record)
      end
    end
  end

  describe "#setup_parser" do
    it "should initialize a parser" do
      worker.send(:setup_parser)
      worker.parser.should eq parser
    end

    it "should load the parser file" do
      parser.should_receive(:load_file)
      worker.send(:setup_parser)
    end

    it "should initialize the parser class" do
      worker.send(:setup_parser)
      worker.parser_class.should eq TestClass
    end

    it "should set the environment of the job to the parser_class" do
      worker.send(:setup_parser)
      worker.parser_class.environment.should eq "production"
    end
  end

  describe "#enrichment_options" do
    let(:block) { Proc.new { "Hi" } }

    before(:each) do
      parser.stub(:enrichment_definitions) { {ndha_rights: {block: block}} }
    end

    it "should fetch the enrichment definition options" do
      job.enrichment = "ndha_rights"
      worker.send(:setup_parser)
      worker.send(:enrichment_options).should eq({block: block})
    end
  end

  describe "#enrichment_class" do
    let(:block) { Proc.new { "Hi" } }

    before(:each) do
      parser.stub(:enrichment_definitions) { {ndha_rights: {block: block}} }
      job.enrichment = "ndha_rights"
      worker.send(:setup_parser)
    end

    it "defaults to HarvesterCore::Enrichment" do
      worker.send(:enrichment_class).should eq HarvesterCore::Enrichment
    end

    it "uses a the custom TapuhiRelationships enrichment" do
      parser.stub(:enrichment_definitions) { {ndha_rights: {type: "TapuhiRecords"}} }
      worker.send(:enrichment_class).should eq HarvesterCore::TapuhiRecordsEnrichment
    end
  end

  describe "#post_to_api" do
    let(:record) { mock(:record, id: 123) }
    let(:enrichment) { mock(:enrichment, record: record, record_attributes: {'1' => {title: 'foo'}, '2' => {category: 'books'}} ) }

    it "enqueues an ApiUpdate job with record_id, attributes and enrichment_job_id for each enriched record" do
      worker.send(:post_to_api, enrichment)
      expect(ApiUpdateWorker).to have_enqueued_job("/harvester/records/2/sources.json", {source: {category: 'books'}, required_sources: []}, job.id)
      expect(ApiUpdateWorker).to have_enqueued_job("/harvester/records/1/sources.json", {source: {title: 'foo'}, required_sources: []}, job.id)
    end

    it "should increment the records count on the job" do
      job.should_receive(:increment_records_count!).twice
      worker.send(:post_to_api, enrichment)
    end

    context "required sources" do
      it "should send the required enricments to the api" do
        job.stub(:required_enrichments) { [:ndha_rights] }
        worker.send(:post_to_api, enrichment)
        expect(ApiUpdateWorker).to have_enqueued_job("/harvester/records/1/sources.json", {source: {title: 'foo'}, required_sources: [:ndha_rights]}, job.id)
      end
    end
  end
end