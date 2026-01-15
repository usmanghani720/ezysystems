# lib/tasks/stripe_backfill_connected_transactions.rake
# Usage examples:
#   bundle exec rake stripe:backfill_connected_transactions
#   bundle exec rake stripe:backfill_connected_transactions[30]
#   bundle exec rake stripe:backfill_connected_transactions[90,500]
#   bundle exec rake stripe:backfill_connected_transactions[365,2000,true]   # dry_run
#
# Args:
#   days_back (default 90)            - backfill window
#   max_per_account (default 1000)    - safety cap per connected account
#   dry_run (default false)           - print actions only, do not write DB

namespace :stripe do
    desc "Backfill ConnectedTransaction rows for all connected accounts (one-time)"
    task :backfill_connected_transactions, [:days_back, :max_per_account, :dry_run] => :environment do |_, args|
      require "stripe"
  
      Stripe.api_key = ENV.fetch("STRIPE_SECRET_KEY")
  
      days_back       = (args[:days_back].presence || 180).to_i
      max_per_account = (args[:max_per_account].presence || 1000).to_i
      dry_run         = ActiveModel::Type::Boolean.new.cast(args[:dry_run])
  
      created_gte = days_back.days.ago.to_i
  
      account_ids = User.where.not(stripe_user_id: [nil, ""])
                        .pluck(:stripe_user_id)
                        .uniq
  
      puts "Stripe backfill starting"
      puts "Accounts: #{account_ids.size}"
      puts "Window: last #{days_back} days (created >= #{Time.at(created_gte)})"
      puts "Max per account: #{max_per_account}"
      puts "Dry run: #{dry_run}"
      puts "-" * 60
  
      total_upserts = 0
      total_seen    = 0
      failures      = 0
  
      account_ids.each_with_index do |acct, idx|
        puts "\n[#{idx + 1}/#{account_ids.size}] acct=#{acct}"
  
        seen_for_acct   = 0
        upserts_for_acct = 0
        starting_after  = nil
  
        loop do
          break if seen_for_acct >= max_per_account
  
          list_params = {
            limit: 100,
            created: { gte: created_gte },
            expand: [
              "data.customer",
              "data.payment_method",
              "data.latest_charge"
            ]
          }
          list_params[:starting_after] = starting_after if starting_after.present?
  
          pis = with_stripe_retries(acct: acct, label: "PaymentIntent.list") do
            Stripe::PaymentIntent.list(list_params, { stripe_account: acct })
          end
  
          break if pis.nil? # if retries exhausted and returned nil
          break if pis.data.blank?
  
          pis.data.each do |pi|
            seen_for_acct += 1
            total_seen    += 1
            break if seen_for_acct > max_per_account
  
            begin
              ch   = pi.latest_charge
              pm   = pi.payment_method
              card = pm&.card
  
              attrs = {
                stripe_account_id: acct,
                payment_intent_id: pi.id,
                charge_id: ch&.id,
  
                amount: pi.amount,
                currency: pi.currency&.upcase,
                status: pi.status,
  
                customer_email: pi.customer&.respond_to?(:email) ? pi.customer.email : nil,
                payment_method_label: card ? "#{card.brand&.upcase} •••• #{card.last4}" : nil,
  
                refunded: ch ? (ch.refunded || ch.amount_refunded.to_i > 0) : false,
                amount_refunded: ch ? ch.amount_refunded.to_i : 0,
  
                created_at_stripe: pi.created.to_i,
                updated_at: Time.current,
                created_at: Time.current
              }
  
              if dry_run
                puts "  [DRY] upsert PI=#{pi.id} status=#{pi.status} amount=#{pi.amount} charge=#{ch&.id}"
              else
                ConnectedTransaction.upsert(attrs, unique_by: :payment_intent_id)
              end
  
              upserts_for_acct += 1
              total_upserts    += 1
  
            rescue => e
              failures += 1
              warn "  [WARN] Failed PI=#{pi.id}: #{e.class} #{e.message}"
            end
          end
  
          starting_after = pis.data.last.id
          break unless pis.has_more
        end
  
        puts "  Done acct=#{acct} seen=#{seen_for_acct} upserts=#{upserts_for_acct}"
      end
  
      puts "\n" + "-" * 60
      puts "Backfill complete"
      puts "Total seen: #{total_seen}"
      puts "Total upserts: #{total_upserts}"
      puts "Failures: #{failures}"
    end
  
    # Basic retry helper for Stripe rate limits / transient failures.
    def with_stripe_retries(acct:, label:, max_attempts: 5)
      attempt = 0
      begin
        attempt += 1
        yield
      rescue Stripe::RateLimitError, Stripe::APIConnectionError, Stripe::StripeError => e
        if attempt < max_attempts
          sleep_seconds = (2**attempt) + rand(0.0..0.5)
          warn "  [#{label}] Stripe error (attempt #{attempt}/#{max_attempts}) acct=#{acct}: #{e.class} #{e.message} -> sleeping #{sleep_seconds.round(2)}s"
          sleep sleep_seconds
          retry
        end
        warn "  [#{label}] Giving up after #{attempt} attempts acct=#{acct}: #{e.class} #{e.message}"
        nil
      end
    end
  end
  