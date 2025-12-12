# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#

#DailyBillingJob.perform_now()

# User.where.not(stripe_user_id: nil).each do |user|
#     @code = rand(8 ** 8)
#     user.update(unique_code: @code)
#     if user.role != "admin"
#         user.update(role: 'vendor')
#     end
# end


User.all.each do |user|
    @code = rand(8 ** 8)
    user.update(unique_code: @code)
    if user.role != "admin"
        user.update(role: 'vendor')
    end
    if user.role == "vendor" && user.unique_code.blank?
        user.update(unique_code: @code)
    end
end


