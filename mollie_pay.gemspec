require_relative "lib/mollie_pay/version"

Gem::Specification.new do |spec|
  spec.name        = "mollie_pay"
  spec.version     = MolliePay::VERSION
  spec.authors     = [ "Peter Berkenbosch" ]
  spec.email       = [ "info@peterberkenbosch.nl" ]
  spec.homepage    = "https://github.com/peterberkenbosch/mollie_pay"
  spec.summary     = "Mollie payments engine for Rails SaaS applications"
  spec.description = "A headless Rails engine that bridges Mollie payments with SaaS billing patterns. Subscriptions, mandates, one-off payments and webhooks."
  spec.license     = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the "allowed_push_host"
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/peterberkenbosch/mollie_pay"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 8.1.2"
  spec.add_dependency "mollie-api-ruby", ">= 4.19.0"
end
