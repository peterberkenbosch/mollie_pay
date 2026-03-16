module MolliePay
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Install MolliePay: create initializer and copy migrations"

      class_option :skip_migrations, type: :boolean, default: false,
        desc: "Skip copying and running migrations"

      def copy_initializer
        template "initializer.rb.tt", "config/initializers/mollie_pay.rb"
      end

      def install_migrations
        return if options[:skip_migrations]

        rails_command "mollie_pay:install:migrations", inline: true
      end

      def run_migrations
        return if options[:skip_migrations]

        rails_command "db:migrate", inline: true
      end

      def print_post_install_instructions
        say ""
        say "MolliePay installed successfully!", :green
        say ""
        say "Add the following to your config/routes.rb:", :yellow
        say ""
        say '  mount MolliePay::Engine => "/mollie_pay"'
        say ""
        say "Then include MolliePay::Billable in your billable model:", :yellow
        say ""
        say "  class User < ApplicationRecord"
        say "    include MolliePay::Billable"
        say "  end"
        say ""
      end
    end
  end
end
