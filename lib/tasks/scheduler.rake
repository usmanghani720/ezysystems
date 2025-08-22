desc "daily_billing_job"
task daily_billing_job: :environment do
  today = Time.now.to_date
  if today.day == 1
    DailyBillingJob.perform_now
    Rails.logger.info "[monthly] Enqueued MyMonthlyJob for #{today}"
  else   
    Rails.logger.info "[monthly] Skipped; today=#{today}"
  end
end