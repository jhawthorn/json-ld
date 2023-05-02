# frozen_string_literal: true

require_relative 'spec_helper'

unless ENV['CI']
  describe JSON::LD do
    describe "test suite" do
      require_relative 'suite_helper'
      %w[
        expand
        compact
        flatten
        fromRdf
        toRdf
      ].each do |partial|
        m = Fixtures::SuiteTest::Manifest.open("#{Fixtures::SuiteTest::STAR_SUITE}#{partial}-manifest.jsonld")
        describe m.name do
          m.entries.each do |t|
            specify "#{t.property('@id')}: #{t.name}#{' (negative test)' unless t.positiveTest?}" do
              t.options[:ordered] = false
              expect { t.run self }.not_to write.to(:error)
            end
          end
        end
      end
    end
  end
end
