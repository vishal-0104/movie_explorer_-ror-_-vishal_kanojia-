# frozen_string_literal: true
require 'rails_helper'

RSpec.configure do |config|
  config.swagger_root = Rails.root.join('swagger').to_s
  config.swagger_docs = {
    'v1/swagger.yaml' => YAML.load_file(Rails.root.join('swagger/v1/swagger.yaml'))
  }

  config.swagger_format = :yaml
end