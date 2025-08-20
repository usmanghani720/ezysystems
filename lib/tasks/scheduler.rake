desc "daily_billing_job"
task daily_billing_job: :environment do
  DailyBillingJob.perform_now
end