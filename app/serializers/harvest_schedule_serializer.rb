class HarvestScheduleSerializer < ActiveModel::Serializer

  attributes :id, :parser_id, :start_time, :cron, :frequency, :at_hour, :at_minutes, :offset, :environment
  attributes :next_run_at, :last_run_at, :recurrent, :incremental, :enrichments

end