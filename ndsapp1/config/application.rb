require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Ndsapp1
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 5.1

    config.after_initialize do
      puts 'hi'
      update_database
      puts 'bye'
    end

    def update_database
      file_name_array = Dir.glob("/home/scott/development/nds/files_delta/*").collect do |fnp|
        'files_delta/'+File.basename(fnp)
      end
      request_type  = :delta
      file_name_array.sort.each do |file_name|
        puts file_name
        req = RequestResponse.new(:request_type => request_type)
        req.create_pretty_response_file(file_name)
        req.inspect_notams
      end

    end
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.
  end


end

