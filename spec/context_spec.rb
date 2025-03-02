# frozen_string_literal: true

require_relative 'spec_helper'
require 'rdf/xsd'
require 'rdf/spec/reader'

# Add for testing
module JSON
  module LD
    class Context
      # Retrieve type mappings
      def coercions
        term_definitions.transform_values(&:type_mapping)
      end

      def containers
        term_definitions.transform_values(&:container_mapping)
      end
    end
  end
end

describe JSON::LD::Context do
  subject { context }

  let(:logger) { RDF::Spec.logger }
  let(:context) do
    described_class.new(logger: logger, validate: true, processingMode: "json-ld-1.1", compactToRelative: true)
  end
  let(:remote_doc) do
    JSON::LD::API::RemoteDocument.new('{
      "@context": {
        "xsd": "http://www.w3.org/2001/XMLSchema#",
        "name": "http://xmlns.com/foaf/0.1/name",
        "homepage": {"@id": "http://xmlns.com/foaf/0.1/homepage", "@type": "@id"},
        "avatar": {"@id": "http://xmlns.com/foaf/0.1/avatar", "@type": "@id"}
      }
    }',
      documentUrl: "http://example.com/context",
      contentType: "application/ld+json")
  end

  describe ".parse" do
    let(:ctx) do
      [
        { "foo" => "http://example.com/foo" },
        { "bar" => "foo" }
      ]
    end

    it "merges definitions from each context" do
      ec = described_class.parse(ctx)
      expect(ec.send(:mappings)).to produce({
        "foo" => "http://example.com/foo",
        "bar" => "http://example.com/foo"
      }, logger)
    end
  end

  describe "#parse" do
    context "remote" do
      it "fails given a missing remote @context" do
        described_class.instance_variable_set(:@cache, nil)
        expect(JSON::LD::API).to receive(:documentLoader).with("http://example.com/context",
          anything).and_raise(IOError)
        expect do
          subject.parse("http://example.com/context")
        end.to raise_error(JSON::LD::JsonLdError::LoadingRemoteContextFailed, %r{http://example.com/context})
      end

      it "creates mappings" do
        expect(JSON::LD::API).to receive(:documentLoader).with("http://example.com/context",
          anything).and_yield(remote_doc)
        ec = subject.parse("http://example.com/context")
        expect(ec.send(:mappings)).to produce({
          "xsd" => "http://www.w3.org/2001/XMLSchema#",
          "name" => "http://xmlns.com/foaf/0.1/name",
          "homepage" => "http://xmlns.com/foaf/0.1/homepage",
          "avatar" => "http://xmlns.com/foaf/0.1/avatar"
        }, logger)
      end

      it "retrieves and parses a remote context document in HTML using the context profile" do
        remote_doc =
          JSON::LD::API::RemoteDocument.new(+'
            <html><head>
            <script>Not This</script>
            <script type="application/ld+json">
            {
              "@context": {
                "homepage": {"@id": "http://example.com/this-would-be-wrong", "@type": "@id"},
                "avatar": {"@id": "http://example.com/this-would-be-wrong", "@type": "@id"}
              }
            }
            </script>
            <script type="application/ld+json;profile=http://www.w3.org/ns/json-ld#context">
            {
              "@context": {
                "xsd": "http://www.w3.org/2001/XMLSchema#",
                "name": "http://xmlns.com/foaf/0.1/name",
                "homepage": {"@id": "http://xmlns.com/foaf/0.1/homepage", "@type": "@id"},
                "avatar": {"@id": "http://xmlns.com/foaf/0.1/avatar", "@type": "@id"}
              }
            }
            </script>
            <script type="application/ld+json;profile=http://www.w3.org/ns/json-ld#context">
            {
              "@context": {
                "homepage": {"@id": "http://example.com/this-would-also-be-wrong", "@type": "@id"},
                "avatar": {"@id": "http://example.com/this-would-also-be-wrong", "@type": "@id"}
              }
            }
            </script>
            </head></html>
            ',
            documentUrl: "http://example.com/context",
            contentType: "text/html")

        described_class.instance_variable_set(:@cache, nil)
        expect(JSON::LD::API).to receive(:documentLoader).with("http://example.com/context",
          anything).and_yield(remote_doc)
        ec = subject.parse("http://example.com/context")
        expect(ec.send(:mappings)).to produce({
          "xsd" => "http://www.w3.org/2001/XMLSchema#",
          "name" => "http://xmlns.com/foaf/0.1/name",
          "homepage" => "http://xmlns.com/foaf/0.1/homepage",
          "avatar" => "http://xmlns.com/foaf/0.1/avatar"
        }, logger)
      end

      it "retrieves and parses a remote context document in HTML" do
        remote_doc =
          JSON::LD::API::RemoteDocument.new(+'
            <html><head>
            <script>Not This</script>
            <script type="application/ld+json">
            {
              "@context": {
                "xsd": "http://www.w3.org/2001/XMLSchema#",
                "name": "http://xmlns.com/foaf/0.1/name",
                "homepage": {"@id": "http://xmlns.com/foaf/0.1/homepage", "@type": "@id"},
                "avatar": {"@id": "http://xmlns.com/foaf/0.1/avatar", "@type": "@id"}
              }
            }
            </script>
            <script type="application/ld+json">
            {
              "@context": {
                "homepage": {"@id": "http://example.com/this-would-also-be-wrong", "@type": "@id"},
                "avatar": {"@id": "http://example.com/this-would-also-be-wrong", "@type": "@id"}
              }
            }
            </script>
            </head></html>
            ',
            documentUrl: "http://example.com/context",
            contentType: "text/html")
        described_class.instance_variable_set(:@cache, nil)
        expect(JSON::LD::API).to receive(:documentLoader).with("http://example.com/context",
          anything).and_yield(remote_doc)
        ec = subject.parse("http://example.com/context")
        expect(ec.send(:mappings)).to produce({
          "xsd" => "http://www.w3.org/2001/XMLSchema#",
          "name" => "http://xmlns.com/foaf/0.1/name",
          "homepage" => "http://xmlns.com/foaf/0.1/homepage",
          "avatar" => "http://xmlns.com/foaf/0.1/avatar"
        }, logger)
      end

      it "notes non-existing @context" do
        expect { subject.parse(StringIO.new("{}")) }.to raise_error(JSON::LD::JsonLdError::InvalidRemoteContext)
      end

      it "parses a referenced context at a relative URI" do
        described_class.instance_variable_set(:@cache, nil)
        rd1 = JSON::LD::API::RemoteDocument.new(%({"@context": "context"}), base_uri: "http://example.com/c1")
        expect(JSON::LD::API).to receive(:documentLoader).with("http://example.com/c1", anything).and_yield(rd1)
        expect(JSON::LD::API).to receive(:documentLoader).with("http://example.com/context",
          anything).and_yield(remote_doc)
        ec = subject.parse("http://example.com/c1")
        expect(ec.send(:mappings)).to produce({
          "xsd" => "http://www.w3.org/2001/XMLSchema#",
          "name" => "http://xmlns.com/foaf/0.1/name",
          "homepage" => "http://xmlns.com/foaf/0.1/homepage",
          "avatar" => "http://xmlns.com/foaf/0.1/avatar"
        }, logger)
      end

      context "remote with local mappings" do
        let(:ctx) { ["http://example.com/context", { "integer" => "xsd:integer" }] }

        before { described_class.instance_variable_set(:@cache, nil) }

        it "retrieves and parses a remote context document" do
          expect(JSON::LD::API).to receive(:documentLoader).with("http://example.com/context",
            anything).and_yield(remote_doc)
          ec = subject.parse(ctx)
          expect(ec.send(:mappings)).to produce({
            "xsd" => "http://www.w3.org/2001/XMLSchema#",
            "name" => "http://xmlns.com/foaf/0.1/name",
            "homepage" => "http://xmlns.com/foaf/0.1/homepage",
            "avatar" => "http://xmlns.com/foaf/0.1/avatar",
            "integer" => "http://www.w3.org/2001/XMLSchema#integer"
          }, logger)
        end
      end

      context "pre-loaded remote" do
        let(:ctx) { "http://example.com/preloaded" }

        before(:all) do
          described_class.add_preloaded("http://example.com/preloaded",
            described_class.parse({ 'foo' => "http://example.com/" }))
          described_class.alias_preloaded("https://example.com/preloaded", "http://example.com/preloaded")
        end

        after(:all) { described_class.instance_variable_set(:@cache, nil) }

        it "does not load referenced context" do
          expect(JSON::LD::API).not_to receive(:documentLoader).with(ctx, anything)
          subject.parse(ctx)
        end

        it "does not load aliased context" do
          expect(JSON::LD::API).not_to receive(:documentLoader).with(ctx.sub('http', 'https'), anything)
          subject.parse(ctx.sub('http', 'https'))
        end

        it "uses loaded context" do
          ec = subject.parse(ctx)
          expect(ec.send(:mappings)).to produce({
            "foo" => "http://example.com/"
          }, logger)
        end

        it "uses aliased context" do
          ec = subject.parse(ctx.sub('http', 'https'))
          expect(ec.send(:mappings)).to produce({
            "foo" => "http://example.com/"
          }, logger)
        end
      end
    end

    context "Array" do
      let(:ctx) do
        [
          { "foo" => "http://example.com/foo" },
          { "bar" => "foo" }
        ]
      end

      it "merges definitions from each context" do
        ec = subject.parse(ctx)
        expect(ec.send(:mappings)).to produce({
          "foo" => "http://example.com/foo",
          "bar" => "http://example.com/foo"
        }, logger)
      end

      it "merges definitions from remote contexts" do
        described_class.instance_variable_set(:@cache, nil)
        expect(JSON::LD::API).to receive(:documentLoader).with("http://example.com/context",
          anything).and_yield(remote_doc)
        rd2 = JSON::LD::API::RemoteDocument.new('{
          "@context": {
            "title": {"@id": "http://purl.org/dc/terms/title"}
          }
        }', base_uri: "http://example.com/c2")
        expect(JSON::LD::API).to receive(:documentLoader).with("http://example.com/c2", anything).and_yield(rd2)
        ec = subject.parse(%w[http://example.com/context http://example.com/c2])
        expect(ec.send(:mappings)).to produce({
          "xsd" => "http://www.w3.org/2001/XMLSchema#",
          "name" => "http://xmlns.com/foaf/0.1/name",
          "homepage" => "http://xmlns.com/foaf/0.1/homepage",
          "avatar" => "http://xmlns.com/foaf/0.1/avatar",
          "title" => "http://purl.org/dc/terms/title"
        }, logger)
      end
    end

    context "Hash" do
      it "extracts @language" do
        expect(subject.parse({
          "@language" => "en"
        }).default_language).to produce("en", logger)
      end

      it "extracts @vocab" do
        expect(subject.parse({
          "@vocab" => "http://schema.org/"
        }).vocab).to produce("http://schema.org/", logger)
      end

      it "maps term with IRI value" do
        expect(subject.parse({
          "foo" => "http://example.com/"
        }).send(:mappings)).to produce({
          "foo" => "http://example.com/"
        }, logger)
      end

      it "maps term with blank node value (with deprecation)" do
        expect do
          expect(subject.parse({
            "foo" => "_:bn"
          }).send(:mappings)).to produce({
            "foo" => RDF::Node("bn")
          }, logger)
        end.to write("[DEPRECATION]").to(:error)
      end

      it "maps term with @id" do
        expect(subject.parse({
          "foo" => { "@id" => "http://example.com/" }
        }).send(:mappings)).to produce({
          "foo" => "http://example.com/"
        }, logger)
      end

      it "maps term with blank node @id (with deprecation)" do
        expect do
          expect(subject.parse({
            "foo" => { "@id" => "_:bn" }
          }).send(:mappings)).to produce({
            "foo" => RDF::Node("bn")
          }, logger)
        end.to write("[DEPRECATION]").to(:error)
      end

      it "warns and ignores keyword-like term" do
        expect do
          expect(subject.parse({
            "@foo" => { "@id" => "http://example.org/foo" }
          }).send(:mappings)).to produce({}, logger)
        end.to write("Terms beginning with '@' are reserved").to(:error)
      end

      it "maps '@' as a term" do
        expect do
          expect(subject.parse({
            "@" => { "@id" => "http://example.org/@" }
          }).send(:mappings)).to produce({
            "@" => "http://example.org/@"
          }, logger)
        end.not_to write.to(:error)
      end

      it "maps '@foo.bar' as a term" do
        expect do
          expect(subject.parse({
            "@foo.bar" => { "@id" => "http://example.org/foo.bar" }
          }).send(:mappings)).to produce({
            "@foo.bar" => "http://example.org/foo.bar"
          }, logger)
        end.not_to write.to(:error)
      end

      it "associates @list container mapping with term" do
        expect(subject.parse({
          "foo" => { "@id" => "http://example.com/", "@container" => "@list" }
        }).containers).to produce({
          "foo" => Set["@list"]
        }, logger)
      end

      it "associates @type container mapping with term" do
        expect(subject.parse({
          "foo" => { "@id" => "http://example.com/", "@container" => "@type" }
        }).containers).to produce({
          "foo" => Set["@type"]
        }, logger)
      end

      it "associates @id container mapping with term" do
        expect(subject.parse({
          "foo" => { "@id" => "http://example.com/", "@container" => "@id" }
        }).containers).to produce({
          "foo" => Set["@id"]
        }, logger)
      end

      it "associates @id type mapping with term" do
        expect(subject.parse({
          "foo" => { "@id" => "http://example.com/", "@type" => "@id" }
        }).coercions).to produce({
          "foo" => "@id"
        }, logger)
      end

      it "associates @json type mapping with term" do
        expect(subject.parse({
          "foo" => { "@id" => "http://example.com/", "@type" => "@json" }
        }).coercions).to produce({
          "foo" => "@json"
        }, logger)
      end

      it "associates type mapping with term" do
        expect(subject.parse({
          "foo" => { "@id" => "http://example.com/", "@type" => RDF::XSD.string.to_s }
        }).coercions).to produce({
          "foo" => RDF::XSD.string
        }, logger)
      end

      it "associates language mapping with term" do
        expect(subject.parse({
          "foo" => { "@id" => "http://example.com/", "@language" => "en" }
        }).send(:languages)).to produce({
          "foo" => "en"
        }, logger)
      end

      it "expands chains of term definition/use with string values" do
        expect(subject.parse({
          "foo" => "bar",
          "bar" => "baz",
          "baz" => "http://example.com/"
        }).send(:mappings)).to produce({
          "foo" => "http://example.com/",
          "bar" => "http://example.com/",
          "baz" => "http://example.com/"
        }, logger)
      end

      it "expands terms using @vocab" do
        expect(subject.parse({
          "foo" => "bar",
          "@vocab" => "http://example.com/"
        }).send(:mappings)).to produce({
          "foo" => "http://example.com/bar"
        }, logger)
      end

      context "with null" do
        it "removes @language if set to null" do
          expect(subject.parse([
                                 {
                                   "@language" => "en"
                                 },
                                 {
                                   "@language" => nil
                                 }
                               ]).default_language).to produce(nil, logger)
        end

        it "removes @vocab if set to null" do
          expect(subject.parse([
                                 {
                                   "@vocab" => "http://schema.org/"
                                 },
                                 {
                                   "@vocab" => nil
                                 }
                               ]).vocab).to produce(nil, logger)
        end

        it "removes term if set to null with @vocab" do
          expect(subject.parse([
                                 {
                                   "@vocab" => "http://schema.org/",
                                   "term" => nil
                                 }
                               ]).send(:mappings)).to produce({ "term" => nil }, logger)
        end

        it "loads initial context" do
          init_ec = described_class.new
          nil_ec = subject.parse(nil)
          expect(nil_ec.default_language).to eq init_ec.default_language
          expect(nil_ec.send(:languages)).to eq init_ec.send(:languages)
          expect(nil_ec.send(:mappings)).to eq init_ec.send(:mappings)
          expect(nil_ec.coercions).to eq init_ec.coercions
          expect(nil_ec.containers).to eq init_ec.containers
        end

        it "removes a term definition" do
          expect(subject.parse({ "name" => nil }).send(:mapping, "name")).to be_nil
        end
      end

      context "@propagate" do
        it "generates an InvalidPropagateValue error if not a boolean" do
          expect do
            subject.parse({ '@version' => 1.1,
            '@propagate' => "String" })
          end.to raise_error(JSON::LD::JsonLdError::InvalidPropagateValue)
        end
      end

      context "@import" do
        before { described_class.instance_variable_set(:@cache, nil) }

        it "generates an InvalidImportValue error if not a string" do
          expect do
            subject.parse({ '@version' => 1.1, '@import' => true })
          end.to raise_error(JSON::LD::JsonLdError::InvalidImportValue)
        end

        it "retrieves remote context" do
          expect(JSON::LD::API).to receive(:documentLoader).with("http://example.com/context",
            anything).and_yield(remote_doc)
          ec = subject.parse(JSON.parse(%({
            "@version": 1.1,
            "@import": "http://example.com/context"
          })))
          expect(ec.term_definitions).to include("avatar")
        end
      end
    end

    describe "Syntax Errors" do
      {
        "malformed JSON" => StringIO.new('{"@context": {"foo" "http://malformed/"}'),
        "no @id, @type, or @container" => { "foo" => {} },
        "value as array" => { "foo" => [] },
        "@id as object" => { "foo" => { "@id" => {} } },
        "@id as array of object" => { "foo" => { "@id" => [{}] } },
        "@id as array of null" => { "foo" => { "@id" => [nil] } },
        "@type as object" => { "foo" => { "@type" => {} } },
        "@type as array" => { "foo" => { "@type" => [] } },
        "@type as @list" => { "foo" => { "@type" => "@list" } },
        "@type as @none" => { "@version" => 1.1, "foo" => { "@type" => "@none" } },
        "@type as @set" => { "foo" => { "@type" => "@set" } },
        "@container as object" => { "foo" => { "@container" => {} } },
        "@container as empty array" => { "foo" => { "@container" => [] } },
        "@container as string" => { "foo" => { "@container" => "true" } },
        "@context which is invalid" => { "foo" => { "@context" => { "bar" => [] } } },
        "@language as @id" => { "@language" => { "@id" => "http://example.com/" } },
        "@direction as foo" => { "@direction" => "foo" },
        "@vocab as @id" => { "@vocab" => { "@id" => "http://example.com/" } },
        "@prefix string" => { "foo" => { "@id" => 'http://example.org/', "@prefix" => "str" } },
        "@prefix array" => { "foo" => { "@id" => 'http://example.org/', "@prefix" => [] } },
        "@prefix object" => { "foo" => { "@id" => 'http://example.org/', "@prefix" => {} } },
        "IRI term expands to different IRI" => {
          "ex" => "http://example.com/",
          "ex2" => "http://example.com/2/",
          "ex:foo" => "ex2:foo"
        },
        "IRI term expands to different IRI (reverse)" => {
          "ex" => "http://example.com/",
          "ex2" => "http://example.com/2/",
          "ex:foo" => { "@reverse" => "ex2:foo" }
        }
      }.each do |title, context|
        it title do
          expect do
            ec = subject.parse(context)
            expect(ec.serialize).to produce({}, logger)
          end.to raise_error(JSON::LD::JsonLdError)
        end
      end

      context "1.0" do
        let(:context) { described_class.new(logger: logger, validate: true, processingMode: 'json-ld-1.0') }

        {
          "@context" => { "foo" => { "@id" => 'http://example.org/', "@context" => {} } },
          "@container @id" => { "foo" => { "@container" => "@id" } },
          "@container @type" => { "foo" => { "@container" => "@type" } },
          "@nest" => { "foo" => { "@id" => 'http://example.org/', "@nest" => "@nest" } },
          "@type as @none" => { "foo" => { "@type" => "@none" } },
          "@type as @json" => { "foo" => { "@type" => "@json" } },
          "@prefix" => { "foo" => { "@id" => 'http://example.org/', "@prefix" => true } }
        }.each do |title, context|
          it title do
            expect do
              ec = subject.parse(context)
              expect(ec.serialize).to produce({}, logger)
            end.to raise_error(JSON::LD::JsonLdError)
          end
        end

        it "generates InvalidContextEntry if using @propagate" do
          expect { context.parse({ '@propagate' => true }) }.to raise_error(JSON::LD::JsonLdError::InvalidContextEntry)
        end

        it "generates InvalidContextEntry if using @import" do
          expect do
            context.parse({ '@import' => "location" })
          end.to raise_error(JSON::LD::JsonLdError::InvalidContextEntry)
        end

        (JSON::LD::KEYWORDS - %w[@base @language @version @protected @propagate @vocab]).each do |kw|
          it "does not redefine #{kw} with an @container" do
            expect do
              ec = subject.parse({ kw => { "@container" => "@set" } })
              expect(ec.serialize).to produce({}, logger)
            end.to raise_error(JSON::LD::JsonLdError)
          end
        end
      end

      (JSON::LD::KEYWORDS - %w[@base @direction @language @protected @propagate @import @version @vocab]).each do |kw|
        it "does not redefine #{kw} as a string" do
          expect do
            ec = subject.parse({ kw => "http://example.com/" })
            expect(ec.serialize).to produce({}, logger)
          end.to raise_error(JSON::LD::JsonLdError)
        end

        it "does not redefine #{kw} with an @id" do
          expect do
            ec = subject.parse({ kw => { "@id" => "http://example.com/" } })
            expect(ec.serialize).to produce({}, logger)
          end.to raise_error(JSON::LD::JsonLdError)
        end

        unless kw == '@type'
          it "does not redefine #{kw} with an @container" do
            expect do
              ec = subject.parse({ "@version" => 1.1, kw => { "@container" => "@set" } })
              expect(ec.serialize).to produce({}, logger)
            end.to raise_error(JSON::LD::JsonLdError)
          end
        end

        next unless kw == '@type'

        it "redefines #{kw} with an @container" do
          ec = subject.parse({ kw => { "@container" => "@set" } })
          expect(ec.as_array('@type')).to be_truthy
        end
      end
    end
  end

  describe "#processingMode" do
    it "sets to json-ld-1.1 if @version: 1.1" do
      [
        %({"@version": 1.1}),
        %([{"@version": 1.1}])
      ].each do |str|
        ctx = described_class.parse(JSON.parse(str))
        expect(ctx.processingMode).to eql "json-ld-1.1"
      end
    end

    it "raises InvalidVersionValue if @version out of scope" do
      [
        "1.1",
        "1.0",
        1.0,
        "foo"
      ].each do |vers|
        expect do
          described_class.parse({ "@version" => vers })
        end.to raise_error(JSON::LD::JsonLdError::InvalidVersionValue)
      end
    end

    it "raises ProcessingModeConflict if provided processing mode conflicts with context" do
      expect do
        described_class.parse({ "@version" => 1.1 },
          processingMode: "json-ld-1.0")
      end.to raise_error(JSON::LD::JsonLdError::ProcessingModeConflict)
    end

    it "does not raise ProcessingModeConflict nested context is different from starting context" do
      expect { described_class.parse([{}, { "@version" => 1.1 }]) }.not_to raise_error
    end
  end

  describe "#merge" do
    it "creates a new context with components of each" do
      c2 = described_class.parse({ 'foo' => "http://example.com/" })
      cm = context.merge(c2)
      expect(cm).not_to equal context
      expect(cm).not_to equal c2
      expect(cm.term_definitions).to eq c2.term_definitions
    end
  end

  describe "#serialize" do
    before { described_class.instance_variable_set(:@cache, nil) }

    it "context hash" do
      ctx = { "foo" => "http://example.com/" }

      ec = subject.parse(ctx)
      expect(ec.serialize).to produce({
        "@context" => ctx
      }, logger)
    end

    it "@language" do
      subject.default_language = "en"
      expect(subject.serialize).to produce({
        "@context" => {
          "@language" => "en"
        }
      }, logger)
    end

    it "@vocab" do
      subject.vocab = "http://example.com/"
      expect(subject.serialize).to produce({
        "@context" => {
          "@vocab" => "http://example.com/"
        }
      }, logger)
    end

    it "term mappings" do
      c = subject
        .parse({ 'foo' => "http://example.com/" })
      expect(c.serialize).to produce({
        "@context" => {
          "foo" => "http://example.com/"
        }
      }, logger)
    end

    it "@context" do
      expect(subject.parse({
        "foo" => { "@id" => "http://example.com/", "@context" => { "bar" => "http://example.com/baz" } }
      })
      .serialize).to produce({
        "@context" => {
          "foo" => {
            "@id" => "http://example.com/",
            "@context" => { "bar" => "http://example.com/baz" }
          }
        }
      }, logger)
    end

    it "@type with dependent prefixes in a single context" do
      expect(subject.parse({
        'xsd' => "http://www.w3.org/2001/XMLSchema#",
        'homepage' => { '@id' => RDF::Vocab::FOAF.homepage.to_s, '@type' => '@id' }
      })
      .serialize).to produce({
        "@context" => {
          "xsd" => RDF::XSD.to_uri.to_s,
          "homepage" => { "@id" => RDF::Vocab::FOAF.homepage.to_s, "@type" => "@id" }
        }
      }, logger)
    end

    it "@list with @id definition in a single context" do
      expect(subject.parse({
        'knows' => { '@id' => RDF::Vocab::FOAF.knows.to_s, '@container' => '@list' }
      })
      .serialize).to produce({
        "@context" => {
          "knows" => { "@id" => RDF::Vocab::FOAF.knows.to_s, "@container" => "@list" }
        }
      }, logger)
    end

    it "@set with @id definition in a single context" do
      expect(subject.parse({
        "knows" => { "@id" => RDF::Vocab::FOAF.knows.to_s, "@container" => "@set" }
      })
      .serialize).to produce({
        "@context" => {
          "knows" => { "@id" => RDF::Vocab::FOAF.knows.to_s, "@container" => "@set" }
        }
      }, logger)
    end

    it "@language with @id definition in a single context" do
      expect(subject.parse({
        "name" => { "@id" => RDF::Vocab::FOAF.name.to_s, "@language" => "en" }
      })
      .serialize).to produce({
        "@context" => {
          "name" => { "@id" => RDF::Vocab::FOAF.name.to_s, "@language" => "en" }
        }
      }, logger)
    end

    it "@language with @id definition in a single context and equivalent default" do
      expect(subject.parse({
        "@language" => 'en',
        "name" => { "@id" => RDF::Vocab::FOAF.name.to_s, "@language" => 'en' }
      })
      .serialize).to produce({
        "@context" => {
          "@language" => 'en',
          "name" => { "@id" => RDF::Vocab::FOAF.name.to_s, "@language" => 'en' }
        }
      }, logger)
    end

    it "@language with @id definition in a single context and different default" do
      expect(subject.parse({
        "@language" => 'en',
        "name" => { "@id" => RDF::Vocab::FOAF.name.to_s, "@language" => "de" }
      })
      .serialize).to produce({
        "@context" => {
          "@language" => 'en',
          "name" => { "@id" => RDF::Vocab::FOAF.name.to_s, "@language" => "de" }
        }
      }, logger)
    end

    it "null @language with @id definition in a single context and default" do
      expect(subject.parse({
        "@language" => 'en',
        "name" => { "@id" => RDF::Vocab::FOAF.name.to_s, "@language" => nil }
      })
      .serialize).to produce({
        "@context" => {
          "@language" => 'en',
          "name" => { "@id" => RDF::Vocab::FOAF.name.to_s, "@language" => nil }
        }
      }, logger)
    end

    it "prefix with @type and @list" do
      expect(subject.parse({
        "knows" => { "@id" => RDF::Vocab::FOAF.knows.to_s, "@type" => "@id", "@container" => "@list" }
      })
      .serialize).to produce({
        "@context" => {
          "knows" => { "@id" => RDF::Vocab::FOAF.knows.to_s, "@type" => "@id", "@container" => "@list" }
        }
      }, logger)
    end

    it "prefix with @type and @set" do
      expect(subject.parse({
        "knows" => { "@id" => RDF::Vocab::FOAF.knows.to_s, "@type" => "@id", "@container" => "@set" }
      })
      .serialize).to produce({
        "@context" => {
          "knows" => { "@id" => RDF::Vocab::FOAF.knows.to_s, "@type" => "@id", "@container" => "@set" }
        }
      }, logger)
    end

    it "prefix with @type @json" do
      expect(subject.parse({
        "knows" => { "@id" => RDF::Vocab::FOAF.knows.to_s, "@type" => "@json" }
      })
      .serialize).to produce({
        "@context" => {
          "knows" => { "@id" => RDF::Vocab::FOAF.knows.to_s, "@type" => "@json" }
        }
      }, logger)
    end

    it "Compact IRI with @type" do
      expect(subject.parse({
        "foaf" => RDF::Vocab::FOAF.to_uri.to_s,
        "foaf:knows" => {
          "@container" => "@list"
        }
      })
      .serialize).to produce({
        "@context" => {
          "foaf" => RDF::Vocab::FOAF.to_uri.to_s,
          "foaf:knows" => {
            "@container" => "@list"
          }
        }
      }, logger)
    end

    it "does not use aliased @id in key position" do
      expect(subject.parse({
        "id" => "@id",
        "knows" => { "@id" => RDF::Vocab::FOAF.knows.to_s, "@container" => "@list" }
      })
      .serialize).to produce({
        "@context" => {
          "id" => "@id",
          "knows" => { "@id" => RDF::Vocab::FOAF.knows.to_s, "@container" => "@list" }
        }
      }, logger)
    end

    it "does not use aliased @id in value position" do
      expect(subject.parse({
        "foaf" => RDF::Vocab::FOAF.to_uri.to_s,
        "id" => "@id",
        "foaf:homepage" => {
          "@type" => "@id"
        }
      })
      .serialize).to produce({
        "@context" => {
          "foaf" => RDF::Vocab::FOAF.to_uri.to_s,
          "id" => "@id",
          "foaf:homepage" => {
            "@type" => "@id"
          }
        }
      }, logger)
    end

    it "does not use aliased @type" do
      expect(subject.parse({
        "foaf" => RDF::Vocab::FOAF.to_uri.to_s,
        "type" => "@type",
        "foaf:homepage" => { "@type" => "@id" }
      })
      .serialize).to produce({
        "@context" => {
          "foaf" => RDF::Vocab::FOAF.to_uri.to_s,
          "type" => "@type",
          "foaf:homepage" => { "@type" => "@id" }
        }
      }, logger)
    end

    it "does not use aliased @container" do
      expect(subject.parse({
        "container" => "@container",
        "knows" => { "@id" => RDF::Vocab::FOAF.knows.to_s, "@container" => "@list" }
      })
      .serialize).to produce({
        "@context" => {
          "container" => "@container",
          "knows" => { "@id" => RDF::Vocab::FOAF.knows.to_s, "@container" => "@list" }
        }
      }, logger)
    end

    it "compacts IRIs to Compact IRIs" do
      expect(subject.parse({
        "ex" => 'http://example.org/',
        "term" => { "@id" => "ex:term", "@type" => "ex:datatype" }
      })
      .serialize).to produce({
        "@context" => {
          "ex" => 'http://example.org/',
          "term" => { "@id" => "ex:term", "@type" => "ex:datatype" }
        }
      }, logger)
    end

    it "compacts IRIs using @vocab" do
      expect(subject.parse({
        "@vocab" => 'http://example.org/',
        "term" => { "@id" => "http://example.org/term", "@type" => "datatype" }
      })
      .serialize).to produce({
        "@context" => {
          "@vocab" => 'http://example.org/',
          "term" => { "@type" => "datatype" }
        }
      }, logger)
    end

    context "invalid term definitions" do
      {
        'empty term': {
          input: { "" => "http://blank-term/" }
        },
        'extra key': {
          input: { "foo" => { "@id" => "http://example.com/foo", "@baz" => "foobar" } }
        }
      }.each do |title, params|
        it title do
          expect { subject.parse(params[:input]) }.to raise_error(JSON::LD::JsonLdError::InvalidTermDefinition)
        end
      end
    end
  end

  describe "#to_rb" do
    subject do
      allow(JSON::LD::API).to receive(:documentLoader).with("http://example.com/context",
        anything).and_yield(remote_doc)
      context.parse("http://example.com/context")
    end

    before(:all) { described_class.instance_variable_set(:@cache, nil) }

    it "encodes as utf-8" do
      expect(subject.to_rb).to match(/encoding: utf-8/)
    end

    it "marked as auto-generated" do
      expect(subject.to_rb).to match(/This file generated automatically from/)
    end

    it "includes URL in preloaded" do
      expect(subject.to_rb).to include(%(add_preloaded("http://example.com/context")))
    end

    it "includes processingMode" do
      expect(subject.to_rb).to include(%(processingMode: "json-ld-1.1"))
    end

    it "term mappings" do
      expect(subject.to_rb).to include(%("avatar" => TermDefinition.new("avatar", id: "http://xmlns.com/foaf/0.1/avatar", type_mapping: "@id")))
      expect(subject.to_rb).to include(%("homepage" => TermDefinition.new("homepage", id: "http://xmlns.com/foaf/0.1/homepage", type_mapping: "@id")))
      expect(subject.to_rb).to include(%("name" => TermDefinition.new("name", id: "http://xmlns.com/foaf/0.1/name", simple: true)))
      expect(subject.to_rb).to include(%("xsd" => TermDefinition.new("xsd", id: "http://www.w3.org/2001/XMLSchema#", simple: true, prefix: true)))
    end
  end

  describe "#base=" do
    subject do
      context.parse({
        '@base' => 'http://base/',
        '@vocab' => 'http://vocab/',
        'ex' => 'http://example.org/',
        '_' => 'http://underscore/'
      })
    end

    it "sets new base uri given an absolute uri" do
      subject.base = "http://example.org/"
      expect(subject.base).to eql RDF::URI("http://example.org/")
    end

    it "sets relative URI" do
      subject.base = "foo/bar"
      expect(subject.base).to eql RDF::URI("http://base/foo/bar")
    end
  end

  describe "#vocab=" do
    subject do
      context.parse({
        '@base' => 'http://base/resource'
      })
    end

    it "sets vocab from absolute iri" do
      subject.vocab = "http://example.org/"
      expect(subject.vocab).to eql RDF::URI("http://example.org/")
    end

    it "sets vocab from empty string" do
      subject.vocab = ""
      expect(subject.vocab).to eql RDF::URI("http://base/resource")
    end

    it "sets vocab to blank node (with deprecation)" do
      expect do
        subject.vocab = "_:bn"
      end.to write("[DEPRECATION]").to(:error)
      expect(subject.vocab).to eql "_:bn"
    end

    it "sets vocab from relative IRI" do
      subject.vocab = "relative#"
      expect(subject.vocab).to eql RDF::URI("http://base/relative#")
    end

    it "sets vocab from relative IRI given an existing vocab" do
      subject.vocab = "http://example.org/."
      subject.vocab = "relative#"
      expect(subject.vocab).to eql RDF::URI("http://example.org/.relative#")
    end

    it "sets vocab from relative IRI given an existing vocab which is also relative" do
      subject.vocab = "/rel1"
      subject.vocab = "rel2#"
      expect(subject.vocab).to eql RDF::URI("http://base/rel1rel2#")
    end
  end

  describe "#expand_iri" do
    subject do
      context.parse({
        '@base' => 'http://base/base',
        '@vocab' => 'http://vocab/',
        'ex' => 'http://example.org/',
        '_' => 'http://underscore/'
      })
    end

    it "bnode" do
      expect(subject.expand_iri("_:a")).to be_a(RDF::Node)
    end

    context "keywords" do
      %w[id type].each do |kw|
        it "expands #{kw} to @#{kw}" do
          subject.set_mapping(kw, "@#{kw}")
          expect(subject.expand_iri(kw, vocab: true)).to produce("@#{kw}", logger)
        end
      end
    end

    context "relative IRI" do
      context "with no options" do
        {
          "absolute IRI" => ["http://example.org/", RDF::URI("http://example.org/")],
          "term" => ["ex", RDF::URI("ex")],
          "prefix:suffix" => ["ex:suffix", RDF::URI("http://example.org/suffix")],
          "#frag" => ["#frag", RDF::URI("#frag")],
          "#frag:2" => ["#frag:2",             RDF::URI("#frag:2")],
          "keyword" => ["@type",               "@type"],
          "unmapped" => ["foo",                 RDF::URI("foo")],
          "relative" => ["foo/bar",             RDF::URI("foo/bar")],
          "dotseg" => ["../foo/bar", RDF::URI("../foo/bar")],
          "empty term" => ["", RDF::URI("")],
          "another abs IRI" => ["ex://foo", RDF::URI("ex://foo")],
          "absolute IRI looking like a Compact IRI" =>
                             ["foo:bar",             RDF::URI("foo:bar")],
          "bnode" => ["_:t0", RDF::Node("t0")],
          "_" => ["_",                   RDF::URI("_")],
          "@" => ["@",                   RDF::URI("@")]
        }.each do |title, (input, result)|
          it title do
            expect(subject.expand_iri(input)).to produce(result, logger)
          end
        end
      end

      context "with base IRI" do
        {
          "absolute IRI" => ["http://example.org/", RDF::URI("http://example.org/")],
          "term" => ["ex", RDF::URI("http://base/ex")],
          "prefix:suffix" => ["ex:suffix", RDF::URI("http://example.org/suffix")],
          "#frag" => ["#frag", RDF::URI("http://base/base#frag")],
          "#frag:2" => ["#frag:2",             RDF::URI("http://base/base#frag:2")],
          "keyword" => ["@type",               "@type"],
          "unmapped" => ["foo",                 RDF::URI("http://base/foo")],
          "relative" => ["foo/bar",             RDF::URI("http://base/foo/bar")],
          "dotseg" => ["../foo/bar", RDF::URI("http://base/foo/bar")],
          "empty term" => ["", RDF::URI("http://base/base")],
          "another abs IRI" => ["ex://foo", RDF::URI("ex://foo")],
          "absolute IRI looking like a compact IRI" =>
                             ["foo:bar",             RDF::URI("foo:bar")],
          "bnode" => ["_:t0", RDF::Node("t0")],
          "_" => ["_",                   RDF::URI("http://base/_")],
          "@" => ["@",                   RDF::URI("http://base/@")]
        }.each do |title, (input, result)|
          it title do
            expect(subject.expand_iri(input, documentRelative: true)).to produce(result, logger)
          end
        end
      end

      context "@vocab" do
        {
          "absolute IRI" => ["http://example.org/", RDF::URI("http://example.org/")],
          "term" => ["ex", RDF::URI("http://example.org/")],
          "prefix:suffix" => ["ex:suffix", RDF::URI("http://example.org/suffix")],
          "#frag" => ["#frag", RDF::URI("http://vocab/#frag")],
          "#frag:2" => ["#frag:2",             RDF::URI("http://vocab/#frag:2")],
          "keyword" => ["@type",               "@type"],
          "unmapped" => ["foo",                 RDF::URI("http://vocab/foo")],
          "relative" => ["foo/bar",             RDF::URI("http://vocab/foo/bar")],
          "dotseg" => ["../foo/bar", RDF::URI("http://vocab/../foo/bar")],
          "another abs IRI" => ["ex://foo", RDF::URI("ex://foo")],
          "absolute IRI looking like a compact IRI" =>
                             ["foo:bar",             RDF::URI("foo:bar")],
          "bnode" => ["_:t0", RDF::Node("t0")],
          "_" => ["_",                   RDF::URI("http://underscore/")],
          "@" => ["@",                   RDF::URI("http://vocab/@")]
        }.each do |title, (input, result)|
          it title do
            expect(subject.expand_iri(input, vocab: true)).to produce(result, logger)
          end
        end

        context "set to ''" do
          subject do
            context.parse({
              '@base' => 'http://base/base',
              '@vocab' => '',
              'ex' => 'http://example.org/',
              '_' => 'http://underscore/'
            })
          end

          {
            "absolute IRI" => ["http://example.org/", RDF::URI("http://example.org/")],
            "term" => ["ex", RDF::URI("http://example.org/")],
            "prefix:suffix" => ["ex:suffix", RDF::URI("http://example.org/suffix")],
            "#frag" => ["#frag", RDF::URI("http://base/base#frag")],
            "#frag:2" => ["#frag:2",             RDF::URI("http://base/base#frag:2")],
            "keyword" => ["@type",               "@type"],
            "unmapped" => ["foo",                 RDF::URI("http://base/basefoo")],
            "relative" => ["foo/bar",             RDF::URI("http://base/basefoo/bar")],
            "dotseg" => ["../foo/bar", RDF::URI("http://base/base../foo/bar")],
            "another abs IRI" => ["ex://foo", RDF::URI("ex://foo")],
            "absolute IRI looking like a compact IRI" =>
                               ["foo:bar", RDF::URI("foo:bar")],
            "bnode" => ["_:t0", RDF::Node("t0")],
            "_" => ["_", RDF::URI("http://underscore/")]
          }.each do |title, (input, result)|
            it title do
              expect(subject.expand_iri(input, vocab: true)).to produce(result, logger)
            end
          end
        end

        it "expand-0110" do
          ctx = described_class.parse({
            "@base" => "http://example.com/some/deep/directory/and/file/",
            "@vocab" => "/relative"
          })
          expect(ctx.expand_iri("#fragment-works",
            vocab: true)).to produce("http://example.com/relative#fragment-works", logger)
        end
      end
    end
  end

  describe "#compact_iri" do
    subject do
      c = context.parse({
        '@base' => 'http://base/',
        "xsd" => "http://www.w3.org/2001/XMLSchema#",
        'ex' => 'http://example.org/',
        '_' => 'http://underscore/',
        'rex' => { '@reverse' => "ex" },
        'lex' => { '@id' => 'ex', '@language' => 'en' },
        'tex' => { '@id' => 'ex', '@type' => 'xsd:string' },
        'exp' => { '@id' => 'ex:pert' },
        'experts' => { '@id' => 'ex:perts' }
      })
      logger.clear
      c
    end

    {
      "nil" => [nil, nil],
      "absolute IRI" => ["http://example.com/", "http://example.com/"],
      "prefix:suffix" => ["ex:suffix", "http://example.org/suffix"],
      "unmapped" => %w[foo foo],
      "bnode" => [JSON::LD::JsonLdError::IRIConfusedWithPrefix, RDF::Node("a")],
      "relative" => ["foo/bar", "http://base/foo/bar"],
      "odd Compact IRI" => ["ex:perts", "http://example.org/perts"]
    }.each do |title, (result, input)|
      it title do
        if result.is_a?(Class)
          expect { subject.compact_iri(input) }.to raise_error(result)
        else
          expect(subject.compact_iri(input)).to produce(result, logger)
        end
      end
    end

    context "with :vocab option" do
      {
        "absolute IRI" => ["http://example.com/", "http://example.com/"],
        "prefix:suffix" => ["ex:suffix", "http://example.org/suffix"],
        "keyword" => ["@type", "@type"],
        "unmapped" => %w[foo foo],
        "bnode" => [JSON::LD::JsonLdError::IRIConfusedWithPrefix, RDF::Node("a")],
        "relative" => ["http://base/foo/bar", "http://base/foo/bar"],
        "odd Compact IRI" => ["experts", "http://example.org/perts"]
      }.each do |title, (result, input)|
        it title do
          if result.is_a?(Class)
            expect { subject.compact_iri(input, vocab: true) }.to raise_error(result)
          else
            expect(subject.compact_iri(input, vocab: true)).to produce(result, logger)
          end
        end
      end
    end

    context "with @vocab" do
      before { subject.vocab = "http://example.org/" }

      {
        "absolute IRI" => ["http://example.com/", "http://example.com/"],
        "prefix:suffix" => ["suffix", "http://example.org/suffix"],
        "keyword" => ["@type", "@type"],
        "unmapped" => %w[foo foo],
        "bnode" => [JSON::LD::JsonLdError::IRIConfusedWithPrefix, RDF::Node("a")],
        "relative" => ["http://base/foo/bar", "http://base/foo/bar"],
        "odd Compact IRI" => ["experts", "http://example.org/perts"]
      }.each do |title, (result, input)|
        it title do
          if result.is_a?(Class)
            expect { subject.compact_iri(input, vocab: true) }.to raise_error(result)
          else
            expect(subject.compact_iri(input, vocab: true)).to produce(result, logger)
          end
        end
      end

      it "does not use @vocab if it would collide with a term" do
        subject.set_mapping("name", "http://xmlns.com/foaf/0.1/name")
        subject.set_mapping("ex", nil)
        expect(subject.compact_iri("http://example.org/name", vocab: true))
          .not_to produce("name", logger)
      end

      context "with @vocab: relative" do
        before do
          subject.vocab = nil
          subject.base = 'http://base/base'
        end

        {
          "absolute IRI" => ["http://example.com/", "http://example.com/"],
          "prefix:suffix" => ["ex:suffix", "http://example.org/suffix"],
          "keyword" => ["@type", "@type"],
          "unmapped" => %w[foo foo],
          "bnode" => [JSON::LD::JsonLdError::IRIConfusedWithPrefix, RDF::Node("a")],
          "relative" => ["http://base/foo/bar", "http://base/foo/bar"],
          "odd Compact IRI" => ["experts", "http://example.org/perts"]
        }.each do |title, (result, input)|
          it title do
            if result.is_a?(Class)
              expect { subject.compact_iri(input, vocab: true) }.to raise_error(result)
            else
              expect(subject.compact_iri(input, vocab: true)).to produce(result, logger)
            end
          end
        end
      end
    end

    context "with value" do
      let(:ctx) do
        c = subject.parse({
          "xsd" => RDF::XSD.to_s,
          "plain" => "http://example.com/plain",
          "lang" => { "@id" => "http://example.com/lang", "@language" => "en" },
          "dir" => { "@id" => "http://example.com/dir", "@direction" => "ltr" },
          "langdir" => { "@id" => "http://example.com/langdir", "@language" => "en", "@direction" => "ltr" },
          "bool" => { "@id" => "http://example.com/bool", "@type" => "xsd:boolean" },
          "integer" => { "@id" => "http://example.com/integer", "@type" => "xsd:integer" },
          "double" => { "@id" => "http://example.com/double", "@type" => "xsd:double" },
          "date" => { "@id" => "http://example.com/date", "@type" => "xsd:date" },
          "id" => { "@id" => "http://example.com/id", "@type" => "@id" },
          'graph' => { '@id' => 'http://example.com/graph', '@container' => '@graph' },
          'json' => { '@id' => 'http://example.com/json', '@type' => '@json' },

          "list_plain" => { "@id" => "http://example.com/plain", "@container" => "@list" },
          "list_lang" => { "@id" => "http://example.com/lang", "@language" => "en", "@container" => "@list" },
          "list_bool" => { "@id" => "http://example.com/bool", "@type" => "xsd:boolean", "@container" => "@list" },
          "list_integer" => { "@id" => "http://example.com/integer", "@type" => "xsd:integer",
                              "@container" => "@list" },
          "list_double" => { "@id" => "http://example.com/double", "@type" => "xsd:double", "@container" => "@list" },
          "list_date" => { "@id" => "http://example.com/date", "@type" => "xsd:date", "@container" => "@list" },
          "list_id" => { "@id" => "http://example.com/id", "@type" => "@id", "@container" => "@list" },
          "list_graph" => { "@id" => "http://example.com/graph", "@type" => "@id", "@container" => "@list" },

          "set_plain" => { "@id" => "http://example.com/plain", "@container" => "@set" },
          "set_lang" => { "@id" => "http://example.com/lang", "@language" => "en", "@container" => "@set" },
          "set_bool" => { "@id" => "http://example.com/bool", "@type" => "xsd:boolean", "@container" => "@set" },
          "set_integer" => { "@id" => "http://example.com/integer", "@type" => "xsd:integer", "@container" => "@set" },
          "set_double" => { "@id" => "http://example.com/double", "@type" => "xsd:double", "@container" => "@set" },
          "set_date" => { "@id" => "http://example.com/date", "@type" => "xsd:date", "@container" => "@set" },
          "set_id" => { "@id" => "http://example.com/id", "@type" => "@id", "@container" => "@set" },
          'set_graph' => { '@id' => 'http://example.com/graph', '@container' => ['@graph', '@set'] },

          "map_lang" => { "@id" => "http://example.com/lang", "@container" => "@language" },

          "set_map_lang" => { "@id" => "http://example.com/lang", "@container" => ["@language", "@set"] }
        })
        logger.clear
        c
      end

      # Prefered sets and maps over non sets or maps
      {
        "set_plain" => [{ "@value" => "foo" }],
        "map_lang" => [{ "@value" => "en", "@language" => "en" }],
        "set_bool" => [{ "@value" => "true", "@type" => "http://www.w3.org/2001/XMLSchema#boolean" }],
        "set_integer" => [{ "@value" => "1", "@type" => "http://www.w3.org/2001/XMLSchema#integer" }],
        "set_id" => [{ "@id" => "http://example.org/id" }],
        "graph" => [{ "@graph" => [{ "@id" => "http://example.org/id" }] }],
        'json' => [{ "@value" => { "some" => "json" }, "@type" => "@json" }],
        'dir' => [{ "@value" => "dir", "@direction" => "ltr" }],
        'langdir' => [{ "@value" => "lang dir", "@language" => "en", "@direction" => "ltr" }]
      }.each do |prop, values|
        context "uses #{prop}" do
          values.each do |value|
            it "for #{value.inspect}" do
              expect(ctx.compact_iri("http://example.com/#{prop.sub(/^\w+_/, '')}", value: value, vocab: true))
                .to produce(prop, logger)
            end
          end
        end
      end

      # @language and @type with @list
      context "for @list" do
        {
          "list_plain" => [
            [{ "@value" => "foo" }],
            [{ "@value" => "foo" }, { "@value" => "bar" }, { "@value" => "baz" }],
            [{ "@value" => "foo" }, { "@value" => "bar" }, { "@value" => 1 }],
            [{ "@value" => "foo" }, { "@value" => "bar" }, { "@value" => 1.1 }],
            [{ "@value" => "foo" }, { "@value" => "bar" }, { "@value" => true }],
            [{ "@value" => "foo" }, { "@value" => "bar" }, { "@value" => 1 }],
            [{ "@value" => "de", "@language" => "de" }, { "@value" => "jp", "@language" => "jp" }],
            [{ "@value" => true }], [{ "@value" => false }],
            [{ "@value" => 1 }], [{ "@value" => 1.1 }]
          ],
          "list_lang" => [[{ "@value" => "en", "@language" => "en" }]],
          "list_bool" => [[{ "@value" => "true", "@type" => RDF::XSD.boolean.to_s }]],
          "list_integer" => [[{ "@value" => "1", "@type" => RDF::XSD.integer.to_s }]],
          "list_double" => [[{ "@value" => "1", "@type" => RDF::XSD.double.to_s }]],
          "list_date" => [[{ "@value" => "2012-04-17", "@type" => RDF::XSD.date.to_s }]]
        }.each do |prop, values|
          context "uses #{prop}" do
            values.each do |value|
              it "for #{{ '@list' => value }.inspect}" do
                expect(ctx.compact_iri("http://example.com/#{prop.sub(/^\w+_/, '')}", value: { "@list" => value },
                  vocab: true))
                  .to produce(prop, logger)
              end
            end
          end
        end
      end
    end

    context "Compact IRI compaction" do
      {
        "nil" => [nil, nil],
        "absolute IRI" => ["http://example.com/", "http://example.com/"],
        "prefix:suffix" => ["ex:suffix", "http://example.org/suffix"],
        "unmapped" => %w[foo foo],
        "bnode" => [JSON::LD::JsonLdError::IRIConfusedWithPrefix, RDF::Node("a")],
        "relative" => ["foo/bar", "http://base/foo/bar"],
        "odd Compact IRI" => ["ex:perts", "http://example.org/perts"]
      }.each do |title, (result, input)|
        it title do
          if result.is_a?(Class)
            expect { subject.compact_iri(input) }.to raise_error(result)
          else
            expect(subject.compact_iri(input)).to produce(result, logger)
          end
        end
      end

      context "and @vocab" do
        before { subject.vocab = "http://example.org/" }

        {
          "absolute IRI" => ["http://example.com/", "http://example.com/"],
          "prefix:suffix" => ["suffix", "http://example.org/suffix"],
          "keyword" => ["@type", "@type"],
          "unmapped" => %w[foo foo],
          "bnode" => [JSON::LD::JsonLdError::IRIConfusedWithPrefix, RDF::Node("a")],
          "relative" => ["http://base/foo/bar", "http://base/foo/bar"],
          "odd Compact IRI" => ["experts", "http://example.org/perts"]
        }.each do |title, (result, input)|
          it title do
            if result.is_a?(Class)
              expect { subject.compact_iri(input, vocab: true) }.to raise_error(result)
            else
              expect(subject.compact_iri(input, vocab: true)).to produce(result, logger)
            end
          end
        end
      end
    end

    context "compact-0018" do
      let(:ctx) do
        subject.parse(JSON.parse(%({
          "id1": "http://example.com/id1",
          "type1": "http://example.com/t1",
          "type2": "http://example.com/t2",
          "@language": "de",
          "term": {
            "@id": "http://example.com/term"
          },
          "term1": {
            "@id": "http://example.com/term",
            "@container": "@list"
          },
          "term2": {
            "@id": "http://example.com/term",
            "@container": "@list",
            "@language": "en"
          },
          "term3": {
            "@id": "http://example.com/term",
            "@container": "@list",
            "@language": null
          },
          "term4": {
            "@id": "http://example.com/term",
            "@container": "@list",
            "@type": "type1"
          },
          "term5": {
            "@id": "http://example.com/term",
            "@container": "@list",
            "@type": "type2"
          }
        })))
      end

      {
        "term" => [
          '{ "@value": "v0.1", "@language": "de" }',
          '{ "@value": "v0.2", "@language": "en" }',
          '{ "@value": "v0.3"}',
          '{ "@value": 4}',
          '{ "@value": true}',
          '{ "@value": false}'
        ],
        "term1" => '{
          "@list": [
            { "@value": "v1.1", "@language": "de" },
            { "@value": "v1.2", "@language": "en" },
            { "@value": "v1.3"},
            { "@value": 14},
            { "@value": true},
            { "@value": false}
          ]
        }',
        "term2" => '{
          "@list": [
            { "@value": "v2.1", "@language": "en" },
            { "@value": "v2.2", "@language": "en" },
            { "@value": "v2.3", "@language": "en" },
            { "@value": "v2.4", "@language": "en" },
            { "@value": "v2.5", "@language": "en" },
            { "@value": "v2.6", "@language": "en" }
          ]
        }',
        "term3" => '{
          "@list": [
            { "@value": "v3.1"},
            { "@value": "v3.2"},
            { "@value": "v3.3"},
            { "@value": "v3.4"},
            { "@value": "v3.5"},
            { "@value": "v3.6"}
          ]
        }',
        "term4" => '{
          "@list": [
            { "@value": "v4.1", "@type": "http://example.com/t1" },
            { "@value": "v4.2", "@type": "http://example.com/t1" },
            { "@value": "v4.3", "@type": "http://example.com/t1" },
            { "@value": "v4.4", "@type": "http://example.com/t1" },
            { "@value": "v4.5", "@type": "http://example.com/t1" },
            { "@value": "v4.6", "@type": "http://example.com/t1" }
          ]
        }',
        "term5" => '{
          "@list": [
            { "@value": "v5.1", "@type": "http://example.com/t2" },
            { "@value": "v5.2", "@type": "http://example.com/t2" },
            { "@value": "v5.3", "@type": "http://example.com/t2" },
            { "@value": "v5.4", "@type": "http://example.com/t2" },
            { "@value": "v5.5", "@type": "http://example.com/t2" },
            { "@value": "v5.6", "@type": "http://example.com/t2" }
          ]
        }'
      }.each do |term, value|
        [value].flatten.each do |v|
          it "Uses #{term} for #{v}" do
            expect(ctx.compact_iri("http://example.com/term", value: JSON.parse(v), vocab: true))
              .to produce(term, logger)
          end
        end
      end
    end

    context "compact-0020" do
      let(:ctx) do
        subject.parse({
          "ex" => "http://example.org/ns#",
          "ex:property" => { "@container" => "@list" }
        })
      end

      it "Compact @id that is a property IRI when @container is @list" do
        expect(ctx.compact_iri("http://example.org/ns#property", vocab: false))
          .to produce("ex:property", logger)
      end
    end

    context "compact-0041" do
      let(:ctx) do
        subject.parse({ "name" => { "@id" => "http://example.com/property", "@container" => "@list" } })
      end

      it "Does not use @list with @index" do
        expect(ctx.compact_iri("http://example.com/property", value: {
          "@list" => ["one item"],
          "@index" => "an annotation"
        })).to produce("http://example.com/property", logger)
      end
    end
  end

  describe "#expand_value" do
    subject do
      ctx = context.parse({
        "dc" => RDF::Vocab::DC.to_uri.to_s,
        "ex" => "http://example.org/",
        "foaf" => RDF::Vocab::FOAF.to_uri.to_s,
        "xsd" => "http://www.w3.org/2001/XMLSchema#",
        "foaf:age" => { "@type" => "xsd:integer" },
        "foaf:knows" => { "@type" => "@id" },
        "dc:created" => { "@type" => "xsd:date" },
        "ex:integer" => { "@type" => "xsd:integer" },
        "ex:double" => { "@type" => "xsd:double" },
        "ex:boolean" => { "@type" => "xsd:boolean" },
        "ex:none" => { "@type" => "@none" },
        "ex:json" => { "@type" => "@json" }
      })
      logger.clear
      ctx
    end

    %w[boolean integer string dateTime date time].each do |dt|
      it "expands datatype xsd:#{dt}" do
        expect(subject.expand_value("foo",
          RDF::XSD[dt])).to produce({ "@id" => "http://www.w3.org/2001/XMLSchema##{dt}" }, logger)
      end
    end

    {
      "absolute IRI" => ["foaf:knows", "http://example.com/", { "@id" => "http://example.com/" }],
      "term" => ["foaf:knows", "ex", { "@id" => "ex" }],
      "prefix:suffix" => ["foaf:knows", "ex:suffix", { "@id" => "http://example.org/suffix" }],
      "no IRI" => ["foo", "http://example.com/", { "@value" => "http://example.com/" }],
      "no term" => ["foo", "ex", { "@value" => "ex" }],
      "no prefix" => ["foo", "ex:suffix", { "@value" => "ex:suffix" }],
      "integer" => ["foaf:age", "54", { "@value" => "54", "@type" => RDF::XSD.integer.to_s }],
      "date " => ["dc:created", "2011-12-27Z",
                  { "@value" => "2011-12-27Z", "@type" => RDF::XSD.date.to_s }],
      "native boolean" => ["foo", true,                           { "@value" => true }],
      "native integer" => ["foo", 1,                              { "@value" => 1 }],
      "native double" => ["foo", 1.1e1, { "@value" => 1.1E1 }],
      "native date" => ["foo", Date.parse("2011-12-27"),
                        { "@value" => "2011-12-27", "@type" => RDF::XSD.date.to_s }],
      "native dateTime" => ["foo", DateTime.parse("2011-12-27T10:11:12Z"),
                            { "@value" => "2011-12-27T10:11:12Z", "@type" => RDF::XSD.dateTime.to_s }],
      "ex:none string" => ["ex:none", "foo", { "@value" => "foo" }],
      "ex:none boolean" => ["ex:none", true,                       { "@value" => true }],
      "ex:none integer" => ["ex:none", 1,                          { "@value" => 1 }],
      "ex:none double" => ["ex:none", 1.1e1,                      { "@value" => 1.1E1 }],
      "ex:json string" => ["ex:json", "foo",                      { "@value" => "foo", "@type" => "@json" }],
      "ex:json boolean" => ["ex:json", true,                       { "@value" => true, "@type" => "@json" }],
      "ex:json integer" => ["ex:json", 1,                          { "@value" => 1, "@type" => "@json" }],
      "ex:json double" => ["ex:json", 1.1e1, { "@value" => 1.1e1, "@type" => "@json" }],
      "ex:json object" => ["ex:json", { "foo" => "bar" },
                           { "@value" => { "foo" => "bar" }, "@type" => "@json" }],
      "ex:json array" => ["ex:json", [{ "foo" => "bar" }],
                          { "@value" => [{ "foo" => "bar" }], "@type" => "@json" }]
    }.each do |title, (key, compacted, expanded)|
      it title do
        expect(subject.expand_value(key, compacted)).to produce(expanded, logger)
      end
    end

    context "@language" do
      before { subject.default_language = "en" }

      {
        "no IRI" => ["foo", "http://example.com/",
                     { "@value" => "http://example.com/", "@language" => "en" }],
        "no term" => ["foo", "ex", { "@value" => "ex", "@language" => "en" }],
        "no prefix" => ["foo", "ex:suffix", { "@value" => "ex:suffix", "@language" => "en" }],
        "native boolean" => ["foo",         true,                   { "@value" => true }],
        "native integer" => ["foo",         1,                      { "@value" => 1 }],
        "native double" => ["foo", 1.1, { "@value" => 1.1 }]
      }.each do |title, (key, compacted, expanded)|
        it title do
          expect(subject.expand_value(key, compacted)).to produce(expanded, logger)
        end
      end
    end

    context "coercion" do
      before { subject.default_language = "en" }

      {
        "boolean-boolean" => ["ex:boolean", true,   { "@value" => true, "@type" => RDF::XSD.boolean.to_s }],
        "boolean-integer" => ["ex:integer", true,   { "@value" => true, "@type" => RDF::XSD.integer.to_s }],
        "boolean-double" => ["ex:double", true, { "@value" => true, "@type" => RDF::XSD.double.to_s }],
        "boolean-json" => ["ex:json", true, { "@value" => true, "@type" => '@json' }],
        "double-boolean" => ["ex:boolean", 1.1, { "@value" => 1.1, "@type" => RDF::XSD.boolean.to_s }],
        "double-double" => ["ex:double", 1.1, { "@value" => 1.1, "@type" => RDF::XSD.double.to_s }],
        "double-integer" => ["foaf:age", 1.1, { "@value" => 1.1, "@type" => RDF::XSD.integer.to_s }],
        "double-json" => ["ex:json", 1.1,     { "@value" => 1.1, "@type" => '@json' }],
        "json-json" => ["ex:json", { "foo" => "bar" }, { "@value" => { "foo" => "bar" }, "@type" => '@json' }],
        "integer-boolean" => ["ex:boolean", 1, { "@value" => 1, "@type" => RDF::XSD.boolean.to_s }],
        "integer-double" => ["ex:double", 1, { "@value" => 1, "@type" => RDF::XSD.double.to_s }],
        "integer-integer" => ["foaf:age", 1, { "@value" => 1, "@type" => RDF::XSD.integer.to_s }],
        "integer-json" => ["ex:json", 1, { "@value" => 1, "@type" => '@json' }],
        "string-boolean" => ["ex:boolean", "foo", { "@value" => "foo", "@type" => RDF::XSD.boolean.to_s }],
        "string-double" => ["ex:double", "foo", { "@value" => "foo", "@type" => RDF::XSD.double.to_s }],
        "string-integer" => ["foaf:age", "foo", { "@value" => "foo", "@type" => RDF::XSD.integer.to_s }],
        "string-json" => ["ex:json", "foo", { "@value" => "foo", "@type" => '@json' }]
      }.each do |title, (key, compacted, expanded)|
        it title do
          expect(subject.expand_value(key, compacted)).to produce(expanded, logger)
        end
      end
    end
  end

  describe "#compact_value" do
    subject { ctx }

    let(:ctx) do
      c = context.parse({
        "dc" => RDF::Vocab::DC.to_uri.to_s,
        "ex" => "http://example.org/",
        "foaf" => RDF::Vocab::FOAF.to_uri.to_s,
        "xsd" => RDF::XSD.to_s,
        "langmap" => { "@id" => "http://example.com/langmap", "@container" => "@language" },
        "list" => { "@id" => "http://example.org/list", "@container" => "@list" },
        "nolang" => { "@id" => "http://example.org/nolang", "@language" => nil },
        "dc:created" => { "@type" => RDF::XSD.date.to_s },
        "foaf:age" => { "@type" => RDF::XSD.integer.to_s },
        "foaf:knows" => { "@type" => "@id" },
        "ex:none" => { "@type" => "@none" }
      })
      logger.clear
      c
    end

    {
      "absolute IRI" => ["foaf:knows", "http://example.com/", { "@id" => "http://example.com/" }],
      "prefix:suffix" => ["foaf:knows", "ex:suffix", { "@id" => "http://example.org/suffix" }],
      "integer" => ["foaf:age", "54", { "@value" => "54", "@type" => RDF::XSD.integer.to_s }],
      "date " => ["dc:created", "2011-12-27Z",
                  { "@value" => "2011-12-27Z", "@type" => RDF::XSD.date.to_s }],
      "no IRI" => ["foo", { "@id" => "http://example.com/" }, { "@id" => "http://example.com/" }],
      "no IRI (Compact IRI)" => ["foo", { "@id" => RDF::Vocab::FOAF.Person.to_s },
                                 { "@id" => RDF::Vocab::FOAF.Person.to_s }],
      "no boolean" => ["foo", { "@value" => "true", "@type" => "xsd:boolean" },
                       { "@value" => "true", "@type" => RDF::XSD.boolean.to_s }],
      "no integer" => ["foo", { "@value" => "54", "@type" => "xsd:integer" },
                       { "@value" => "54", "@type" => RDF::XSD.integer.to_s }],
      "no date " => ["foo", { "@value" => "2011-12-27Z", "@type" => "xsd:date" },
                     { "@value" => "2011-12-27Z", "@type" => RDF::XSD.date.to_s }],
      "no string " => ["foo", "string", { "@value" => "string" }],
      "no lang " => ["nolang", "string", { "@value" => "string" }],
      "native boolean" => ["foo", true,                           { "@value" => true }],
      "native integer" => ["foo", 1,                              { "@value" => 1 }],
      "native integer(list)" => ["list", 1,                         { "@value" => 1 }],
      "native double" => ["foo", 1.1e1, { "@value" => 1.1E1 }],
      "ex:none IRI" => ["ex:none", { "@id" => "http://example.com/" }, { "@id" => "http://example.com/" }],
      "ex:none string" => ["ex:none", { "@value" => "string" }, { "@value" => "string" }],
      "ex:none integer" => ["ex:none", { "@value" => "54", "@type" => "xsd:integer" },
                            { "@value" => "54", "@type" => RDF::XSD.integer.to_s }]
    }.each do |title, (key, compacted, expanded)|
      it title do
        expect(subject.compact_value(key, expanded)).to produce(compacted, logger)
      end
    end

    context "@language" do
      {
        "@id" => ["foo", { "@id" => "foo" }, { "@id" => "foo" }],
        "integer" => ["foo", { "@value" => "54", "@type" => "xsd:integer" },
                      { "@value" => "54", "@type" => RDF::XSD.integer.to_s }],
        "date" => ["foo", { "@value" => "2011-12-27Z", "@type" => "xsd:date" },
                   { "@value" => "2011-12-27Z", "@type" => RDF::XSD.date.to_s }],
        "no lang" => ["foo", { "@value" => "foo" },
                      { "@value" => "foo" }],
        "same lang" => ["foo", "foo",
                        { "@value" => "foo", "@language" => "en" }],
        "other lang" => ["foo", { "@value" => "foo", "@language" => "bar" },
                         { "@value" => "foo", "@language" => "bar" }],
        "langmap" => ["langmap", "en",
                      { "@value" => "en", "@language" => "en" }],
        "no lang with @type coercion" => ["dc:created", { "@value" => "foo" },
                                          { "@value" => "foo" }],
        "no lang with @id coercion" => ["foaf:knows", { "@value" => "foo" },
                                        { "@value" => "foo" }],
        "no lang with @language=null" => ["nolang", "string",
                                          { "@value" => "string" }],
        "same lang with @type coercion" => ["dc:created", { "@value" => "foo" },
                                            { "@value" => "foo" }],
        "same lang with @id coercion" => ["foaf:knows", { "@value" => "foo" },
                                          { "@value" => "foo" }],
        "other lang with @type coercion" => ["dc:created", { "@value" => "foo", "@language" => "bar" },
                                             { "@value" => "foo", "@language" => "bar" }],
        "other lang with @id coercion" => ["foaf:knows", { "@value" => "foo", "@language" => "bar" },
                                           { "@value" => "foo", "@language" => "bar" }],
        "native boolean" => ["foo", true,
                             { "@value" => true }],
        "native integer" => ["foo", 1, { "@value" => 1 }],
        "native integer(list)" => ["list", 1, { "@value" => 1 }],
        "native double" => ["foo", 1.1e1,
                            { "@value" => 1.1E1 }]
      }.each do |title, (key, compacted, expanded)|
        it title do
          subject.default_language = "en"
          expect(subject.compact_value(key, expanded)).to produce(compacted, logger)
        end
      end
    end

    context "keywords" do
      before do
        subject.set_mapping("id", "@id")
        subject.set_mapping("type", "@type")
        subject.set_mapping("list", "@list")
        subject.set_mapping("set", "@set")
        subject.set_mapping("language", "@language")
        subject.set_mapping("literal", "@value")
      end

      {
        "@id" => [{ "id" => "http://example.com/" }, { "@id" => "http://example.com/" }],
        "@type" => [{ "literal" => "foo", "type" => "http://example.com/" },
                    { "@value" => "foo", "@type" => "http://example.com/" }],
        "@value" => [{ "literal" => "foo", "language" => "bar" }, { "@value" => "foo", "@language" => "bar" }]
      }.each do |title, (compacted, expanded)|
        it title do
          expect(subject.compact_value("foo", expanded)).to produce(compacted, logger)
        end
      end
    end
  end

  describe "#from_vocabulary" do
    it "must be described"
  end

  describe "#container" do
    subject do
      ctx = context.parse({
        "ex" => "http://example.org/",
        "graph" => { "@id" => "ex:graph", "@container" => "@graph" },
        "graphSet" => { "@id" => "ex:graphSet", "@container" => ["@graph", "@set"] },
        "graphId" => { "@id" => "ex:graphSet", "@container" => ["@graph", "@id"] },
        "graphIdSet" => { "@id" => "ex:graphSet", "@container" => ["@graph", "@id", "@set"] },
        "graphNdx" => { "@id" => "ex:graphSet", "@container" => ["@graph", "@index"] },
        "graphNdxSet" => { "@id" => "ex:graphSet", "@container" => ["@graph", "@index", "@set"] },
        "id" => { "@id" => "ex:idSet", "@container" => "@id" },
        "idSet" => { "@id" => "ex:id", "@container" => ["@id", "@set"] },
        "language" => { "@id" => "ex:language", "@container" => "@language" },
        "langSet" => { "@id" => "ex:languageSet", "@container" => ["@language", "@set"] },
        "list" => { "@id" => "ex:list", "@container" => "@list" },
        "ndx" => { "@id" => "ex:ndx", "@container" => "@index" },
        "ndxSet" => { "@id" => "ex:ndxSet", "@container" => ["@index", "@set"] },
        "set" => { "@id" => "ex:set", "@container" => "@set" },
        "type" => { "@id" => "ex:type", "@container" => "@type" },
        "typeSet" => { "@id" => "ex:typeSet", "@container" => ["@type", "@set"] }
      })
      logger.clear
      ctx
    end

    it "uses TermDefinition" do
      {
        "ex" => Set.new,
        "graph" => Set["@graph"],
        "graphSet" => Set["@graph"],
        "graphId" => Set["@graph", "@id"],
        "graphIdSet" => Set["@graph", "@id"],
        "graphNdx" => Set["@graph", "@index"],
        "graphNdxSet" => Set["@graph", "@index"],
        "id" => Set['@id'],
        "idSet" => Set['@id'],
        "language" => Set['@language'],
        "langSet" => Set['@language'],
        "list" => Set['@list'],
        "ndx" => Set['@index'],
        "ndxSet" => Set['@index'],
        "set" => Set.new,
        "type" => Set['@type'],
        "typeSet" => Set['@type']
      }.each do |defn, container|
        expect(subject.container(subject.term_definitions[defn])).to eq container
      end
    end

    it "#as_array" do
      {
        "ex" => false,
        "graph" => false,
        "graphSet" => true,
        "graphId" => false,
        "graphIdSet" => true,
        "graphNdx" => false,
        "graphNdxSet" => true,
        "id" => false,
        "idSet" => true,
        "language" => false,
        "langSet" => true,
        "list" => true,
        "ndx" => false,
        "ndxSet" => true,
        "set" => true,
        "type" => false,
        "typeSet" => true
      }.each do |defn, as_array|
        expect(subject.as_array?(subject.term_definitions[defn])).to eq as_array
      end
    end

    it "uses array" do
      {
        "ex" => Set.new,
        "graph" => Set["@graph"],
        "graphSet" => Set["@graph"],
        "graphId" => Set["@graph", "@id"],
        "graphIdSet" => Set["@graph", "@id"],
        "graphNdx" => Set["@graph", "@index"],
        "graphNdxSet" => Set["@graph", "@index"],
        "id" => Set['@id'],
        "idSet" => Set['@id'],
        "language" => Set['@language'],
        "langSet" => Set['@language'],
        "list" => Set['@list'],
        "ndx" => Set['@index'],
        "ndxSet" => Set['@index'],
        "set" => Set.new,
        "type" => Set['@type'],
        "typeSet" => Set['@type']
      }.each do |defn, container|
        expect(subject.container(defn)).to eq container
      end
    end
  end

  describe "#language" do
    subject do
      ctx = context.parse({
        "ex" => "http://example.org/",
        "nil" => { "@id" => "ex:nil", "@language" => nil },
        "en" => { "@id" => "ex:en", "@language" => "en" }
      })
      logger.clear
      ctx
    end

    it "uses TermDefinition" do
      expect(subject.language(subject.term_definitions['ex'])).to be_falsey
      expect(subject.language(subject.term_definitions['nil'])).to be_falsey
      expect(subject.language(subject.term_definitions['en'])).to eq 'en'
    end

    it "uses string" do
      expect(subject.language('ex')).to be_falsey
      expect(subject.language('nil')).to be_falsey
      expect(subject.language('en')).to eq 'en'
    end
  end

  describe "#reverse?" do
    subject do
      ctx = context.parse({
        "ex" => "http://example.org/",
        "reverse" => { "@reverse" => "ex:reverse" }
      })
      logger.clear
      ctx
    end

    it "uses TermDefinition" do
      expect(subject).not_to be_reverse(subject.term_definitions['ex'])
      expect(subject).to be_reverse(subject.term_definitions['reverse'])
    end

    it "uses string" do
      expect(subject).not_to be_reverse('ex')
      expect(subject).to be_reverse('reverse')
    end
  end

  describe "#nest" do
    subject do
      ctx = context.parse({
        "ex" => "http://example.org/",
        "nest" => { "@id" => "ex:nest", "@nest" => "@nest" },
        "nest2" => { "@id" => "ex:nest2", "@nest" => "nest-alias" },
        "nest-alias" => "@nest"
      })
      logger.clear
      ctx
    end

    it "uses term" do
      {
        "ex" => nil,
        "nest" => "@nest",
        "nest2" => "nest-alias",
        "nest-alias" => nil
      }.each do |defn, nest|
        expect(subject.nest(defn)).to eq nest
      end
    end

    context "detects error" do
      it "does not allow a keyword other than @nest for the value of @nest" do
        expect do
          context.parse({ "no-keyword-nest" => { "@id" => "http://example/f", "@nest" => "@id" } })
        end.to raise_error JSON::LD::JsonLdError::InvalidNestValue
      end

      it "does not allow @nest with @reverse" do
        expect do
          context.parse({ "no-reverse-nest" => { "@reverse" => "http://example/f", "@nest" => "@nest" } })
        end.to raise_error JSON::LD::JsonLdError::InvalidReverseProperty
      end
    end
  end

  describe "#reverse_term" do
    subject do
      ctx = context.parse({
        "ex" => "http://example.org/",
        "reverse" => { "@reverse" => "ex" }
      })
      logger.clear
      ctx
    end

    it "uses TermDefinition" do
      expect(subject.reverse_term(subject.term_definitions['ex'])).to eql subject.term_definitions['reverse']
      expect(subject.reverse_term(subject.term_definitions['reverse'])).to eql subject.term_definitions['ex']
    end

    it "uses string" do
      expect(subject.reverse_term('ex')).to eql subject.term_definitions['reverse']
      expect(subject.reverse_term('reverse')).to eql subject.term_definitions['ex']
    end
  end

  describe "protected contexts" do
    it "seals a term with @protected true" do
      ctx = context.parse({
        "protected" => { "@id" => "http://example.com/protected", "@protected" => true },
        "unprotected" => { "@id" => "http://example.com/unprotected" }
      })
      expect(ctx.term_definitions["protected"]).to be_protected
      expect(ctx.term_definitions["unprotected"]).not_to be_protected
    end

    it "seals all term with @protected true in context" do
      ctx = context.parse({
        "@protected" => true,
        "protected" => { "@id" => "http://example.com/protected" },
        "protected2" => { "@id" => "http://example.com/protected2" }
      })
      expect(ctx.term_definitions["protected"]).to be_protected
      expect(ctx.term_definitions["protected2"]).to be_protected
    end

    it "does not seal term with @protected: false when context is protected" do
      ctx = context.parse({
        "@protected" => true,
        "protected" => { "@id" => "http://example.com/protected" },
        "unprotected" => { "@id" => "http://example.com/unprotected", "@protected" => false }
      })
      expect(ctx.term_definitions["protected"]).to be_protected
      expect(ctx.term_definitions["unprotected"]).not_to be_protected
    end

    it "does not error when redefining an identical term" do
      c = {
        "protected" => { "@id" => "http://example.com/protected", "@protected" => true }
      }
      ctx = context.parse(c)

      expect { ctx.parse(c) }.not_to raise_error
    end

    it "errors when redefining a protected term" do
      ctx = context.parse({
        "protected" => { "@id" => "http://example.com/protected", "@protected" => true }
      })

      expect do
        ctx.parse({ "protected" => "http://example.com/different" })
      end.to raise_error(JSON::LD::JsonLdError::ProtectedTermRedefinition)
    end

    it "errors when clearing a context having protected terms" do
      ctx = context.parse({
        "protected" => { "@id" => "http://example.com/protected", "@protected" => true }
      })

      expect { ctx.parse(nil) }.to raise_error(JSON::LD::JsonLdError::InvalidContextNullification)
    end
  end

  describe JSON::LD::Context::TermDefinition do
    context "with nothing" do
      subject { described_class.new("term") }

      its(:term) { is_expected.to eq "term" }
      its(:id) { is_expected.to be_nil }
      its(:to_rb) { is_expected.to eq %(TermDefinition.new("term")) }
    end

    context "with id" do
      subject { described_class.new("term", id: "http://example.org/term") }

      its(:term) { is_expected.to eq "term" }
      its(:id) { is_expected.to eq "http://example.org/term" }
      its(:to_rb) { is_expected.to eq %(TermDefinition.new("term", id: "http://example.org/term")) }
    end

    context "with type_mapping" do
      subject { described_class.new("term", type_mapping: "http://example.org/type") }

      its(:type_mapping) { is_expected.to eq "http://example.org/type" }
      its(:to_rb) { is_expected.to eq %(TermDefinition.new("term", type_mapping: "http://example.org/type")) }
    end

    context "with container_mapping @set" do
      subject { described_class.new("term", container_mapping: "@set") }

      its(:container_mapping) { is_expected.to be_empty }
      its(:to_rb) { is_expected.to eq %(TermDefinition.new("term", container_mapping: "@set")) }
    end

    context "with container_mapping @id @set" do
      subject { described_class.new("term", container_mapping: %w[@id @set]) }

      its(:container_mapping) { is_expected.to eq Set['@id'] }
      its(:to_rb) { is_expected.to eq %(TermDefinition.new("term", container_mapping: ["@id", "@set"])) }
    end

    context "with container_mapping @list" do
      subject { described_class.new("term", container_mapping: "@list") }

      its(:container_mapping) { is_expected.to eq Set['@list'] }
      its(:to_rb) { is_expected.to eq %(TermDefinition.new("term", container_mapping: "@list")) }
    end

    context "with language_mapping" do
      subject { described_class.new("term", language_mapping: "en") }

      its(:language_mapping) { is_expected.to eq "en" }
      its(:to_rb) { is_expected.to eq %(TermDefinition.new("term", language_mapping: "en")) }
    end

    context "with reverse_property" do
      subject { described_class.new("term", reverse_property: true) }

      its(:reverse_property) { is_expected.to be_truthy }
      its(:to_rb) { is_expected.to eq %(TermDefinition.new("term", reverse_property: true)) }
    end

    context "with simple" do
      subject { described_class.new("term", simple: true) }

      its(:simple) { is_expected.to be_truthy }
      its(:to_rb) { is_expected.to eq %(TermDefinition.new("term", simple: true)) }
    end
  end
end
