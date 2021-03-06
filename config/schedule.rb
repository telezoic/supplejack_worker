# The Supplejack Worker code is Crown copyright (C) 2014, New Zealand Government,
# and is licensed under the GNU General Public License, version 3.
# See https://github.com/DigitalNZ/supplejack_worker for details.
#
# Supplejack was created by DigitalNZ at the National Library of NZ
# and the Department of Internal Affairs. http://digitalnz.org/supplejack

env :PATH, ENV['PATH'] if @enviroment == 'development'

every :day, at: '2:00am' do
  runner 'HarvestJob.clear_raw_data'
end

every 4.minutes do
  runner 'ExpensiveCrons.call'
end

# Mails the stats for collection to Harvest operator
every 1.day, at: '6:00 am' do
  runner 'CollectionStatistics.email_daily_stats'
end

# Checks source LinkCheckRules and suppress/unsuppress conllection.
every 2.hours do
  runner 'EnqueueSourceChecksWorker.perform_async'
end

# Clears old Sidekiq Jobs from Mongo
every :monday, at: '2:30am' do
  rake 'sidekiq_jobs:purge'
end
