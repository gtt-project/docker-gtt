Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new
  config.lograge.custom_payload do |controller|
    current_user = controller.find_current_user
    user_name = current_user&.logged? ? "#{current_user.login}" : "anonymous"
    user_id = current_user&.logged? ? "#{current_user.id}" : "0"
    {
      remote_ip: controller.request.remote_ip,
      user_name: user_name,
      user_id: user_id
    }
  end
end
