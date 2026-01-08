# lib/tasks/stripe_plans.rake
namespace :stripe do
    desc "Create 6 Stripe products/prices (monthly) and store in DB. Safe to re-run."
    task seed_plans: :environment do
      Stripe.api_key = ENV.fetch("STRIPE_SECRET_KEY")
      currency = ENV.fetch("CURRENCY", "usd")
  
      # Define your 6 plans here (amounts in cents)
      plans = [
        { name: "Core-Monthly",   amount_cents:  1500 },
        { name: "Core-Yearly",     amount_cents: 1200 },
        { name: "Advanced-Monthly",  amount_cents: 2900 },
        { name: "Advanced-Yearly",       amount_cents: 2400 },
        { name: "Ultimate-Monthly",  amount_cents: 4900 },
        { name: "Ultimate-Yearly",amount_cents: 4200 }
      ]
  
      plans.each do |p|
        plan = Plan.find_by(amount_cents: p[:amount_cents], currency: currency)
  
        if plan
          puts "Exists: #{plan.name} #{plan.amount_cents} #{plan.currency} -> #{plan.stripe_price_id}"
          next
        end
  
        product = Stripe::Product.create(
          name: p[:name],
          metadata: {
            plan_amount_cents: p[:amount_cents].to_s,
            currency: currency
          }
        )
  
        price = Stripe::Price.create(
          product: product.id,
          unit_amount: p[:amount_cents],
          currency: currency,
          recurring: { interval: "month" }
        )
  
        Plan.create!(
          name: p[:name],
          amount_cents: p[:amount_cents],
          currency: currency,
          stripe_product_id: product.id,
          stripe_price_id: price.id
        )
  
        puts "Created: #{p[:name]} #{p[:amount_cents]} #{currency} -> #{price.id}"
      end
    end
  end
  