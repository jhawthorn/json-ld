# frozen_string_literal: true

require_relative 'spec_helper'
require 'rdf/spec/writer'

describe JSON::LD::Writer do
  let(:logger) { RDF::Spec.logger }

  after { |example| puts logger if example.exception }

  it_behaves_like 'an RDF::Writer' do
    let(:writer) { described_class.new(StringIO.new, logger: logger) }
  end

  describe ".for" do
    [
      :jsonld,
      "etc/doap.jsonld",
      { file_name:      'etc/doap.jsonld' },
      { file_extension: 'jsonld' },
      { content_type:   'application/ld+json' },
      { content_type:   'application/x-ld+json' }
    ].each do |arg|
      it "discovers with #{arg.inspect}" do
        expect(RDF::Reader.for(arg)).to eq JSON::LD::Reader
      end
    end
  end

  context "simple tests" do
    it "uses full URIs without base" do
      input = %(<http://a/b> <http://a/c> <http://a/d> .)
      expect(serialize(input)).to produce_jsonld([{
        '@id' => "http://a/b",
        "http://a/c" => [{ "@id" => "http://a/d" }]
      }], logger)
    end

    it "uses qname URIs with standard prefix" do
      input = %(<http://xmlns.com/foaf/0.1/b> <http://xmlns.com/foaf/0.1/c> <http://xmlns.com/foaf/0.1/d> .)
      expect(serialize(input, standard_prefixes: true)).to produce_jsonld({
        '@context' => {
          "foaf" => "http://xmlns.com/foaf/0.1/"
        },
        '@id' => "foaf:b",
        "foaf:c" => { "@id" => "foaf:d" }
      }, logger)
    end

    it "uses qname URIs with parsed prefix" do
      input = %(
        <https://senet.org/gm> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://vocab.org/frbr/core#Work> .
        <https://senet.org/gm> <http://purl.org/dc/terms/title> "Rhythm Paradise"@en .
        <https://senet.org/gm> <https://senet.org/ns#unofficialTitle> "Rhythm Tengoku"@en .
        <https://senet.org/gm> <https://senet.org/ns#urlkey> "rhythm-tengoku" .
      )
      expect(serialize(input, prefixes: {
        dc: "http://purl.org/dc/terms/",
        frbr: "http://vocab.org/frbr/core#",
        senet: "https://senet.org/ns#"
      })).to produce_jsonld({
        '@context' => {
          "dc" => "http://purl.org/dc/terms/",
          "frbr" => "http://vocab.org/frbr/core#",
          "senet" => "https://senet.org/ns#"
        },
        '@id' => "https://senet.org/gm",
        "@type" => "frbr:Work",
        "dc:title" => { "@value" => "Rhythm Paradise", "@language" => "en" },
        "senet:unofficialTitle" => { "@value" => "Rhythm Tengoku", "@language" => "en" },
        "senet:urlkey" => "rhythm-tengoku"
      }, logger)
    end

    it "uses CURIEs with empty prefix" do
      input = %(<http://xmlns.com/foaf/0.1/b> <http://xmlns.com/foaf/0.1/c> <http://xmlns.com/foaf/0.1/d> .)
      begin
        expect(serialize(input, prefixes: { "" => RDF::Vocab::FOAF }))
          .to produce_jsonld({
            "@context" => {
              "" => "http://xmlns.com/foaf/0.1/"
            },
            '@id' => ":b",
            ":c" => { "@id" => ":d" }
          }, logger)
      rescue JSON::LD::JsonLdError, JSON::LD::JsonLdError, TypeError => e
        raise("#{e.class}: #{e.message}\n" \
              "#{logger}\n" \
              "Backtrace:\n#{e.backtrace.join("\n")}")
      end
    end

    it "does not use terms if no suffix" do
      input = %(<http://xmlns.com/foaf/0.1/> <http://xmlns.com/foaf/0.1/> <http://xmlns.com/foaf/0.1/> .)
      expect(serialize(input, standard_prefixes: true))
        .not_to produce_jsonld({
          "@context" => { "foaf" => "http://xmlns.com/foaf/0.1/" },
          '@id' => "foaf",
          "foaf" => { "@id" => "foaf" }
        }, logger)
    end

    it "does not use CURIE with illegal local part" do
      input = %(
        @prefix db: <http://dbpedia.org/resource/> .
        @prefix dbo: <http://dbpedia.org/ontology/> .
        db:Michael_Jackson dbo:artistOf <http://dbpedia.org/resource/%28I_Can%27t_Make_It%29_Another_Day> .
      )

      expect(serialize(input, prefixes: {
        "db" => RDF::URI("http://dbpedia.org/resource/"),
        "dbo" => RDF::URI("http://dbpedia.org/ontology/")
      }))
        .to produce_jsonld({
          "@context" => {
            "db" => "http://dbpedia.org/resource/",
            "dbo" => "http://dbpedia.org/ontology/"
          },
          '@id' => "db:Michael_Jackson",
          "dbo:artistOf" => { "@id" => "db:%28I_Can%27t_Make_It%29_Another_Day" }
        }, logger)
    end

    it "does not use provided node identifiers if :unique_bnodes set" do
      input = %(_:a <http://example.com/foo> _:b .)
      result = serialize(input, unique_bnodes: true, context: {})
      expect(result.to_json).to match(/_:g\w+/)
    end

    it "serializes multiple subjects" do
      input = '
        @prefix : <http://www.w3.org/2006/03/test-description#> .
        @prefix dc: <http://purl.org/dc/terms/> .
        <http://example.com/test-cases/0001> a :TestCase .
        <http://example.com/test-cases/0002> a :TestCase .
      '
      expect(serialize(input, prefixes: { "" => "http://www.w3.org/2006/03/test-description#" }))
        .to produce_jsonld({
          '@context' => {
            "" => "http://www.w3.org/2006/03/test-description#",
            "dc" => RDF::Vocab::DC.to_s
          },
          '@graph' => [
            { '@id' => "http://example.com/test-cases/0001", '@type' => ":TestCase" },
            { '@id' => "http://example.com/test-cases/0002", '@type' => ":TestCase" }
          ]
        }, logger)
    end

    it "serializes Wikia OWL example" do
      input = '
        @prefix owl: <http://www.w3.org/2002/07/owl#> .
        @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
        @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
        @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

        <http://data.wikia.com/terms#Character> a owl:Class;
           rdfs:subClassOf _:a .
        _:a a owl:Restriction;
           owl:minQualifiedCardinality "1"^^xsd:nonNegativeInteger;
           owl:onClass <http://data.wikia.com/terms#Element>;
           owl:onProperty <http://data.wikia.com/terms#characterIn> .
      '
      expect(serialize(input, rename_bnodes: false, prefixes: {
        owl: "http://www.w3.org/2002/07/owl#",
        rdfs: "http://www.w3.org/2000/01/rdf-schema#",
        xsd: "http://www.w3.org/2001/XMLSchema#"
      }))
        .to produce_jsonld({
          '@context' => {
            "owl" => "http://www.w3.org/2002/07/owl#",
            "rdf" => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
            "rdfs" => "http://www.w3.org/2000/01/rdf-schema#",
            "xsd" => "http://www.w3.org/2001/XMLSchema#"
          },
          '@graph' => [
            {
              "@id" => "_:a",
              "@type" => "owl:Restriction",
              "owl:minQualifiedCardinality" => { "@value" => "1", "@type" => "xsd:nonNegativeInteger" },
              "owl:onClass" => { "@id" => "http://data.wikia.com/terms#Element" },
              "owl:onProperty" => { "@id" => "http://data.wikia.com/terms#characterIn" }
            },
            {
              "@id" => "http://data.wikia.com/terms#Character",
              "@type" => "owl:Class",
              "rdfs:subClassOf" => { "@id" => "_:a" }
            }
          ]
        }, logger)
    end
  end

  context "RDF-star" do
    {
      'subject-iii': {
        input: RDF::Statement(
          RDF::Statement(
            RDF::URI('http://example/s1'),
            RDF::URI('http://example/p1'),
            RDF::URI('http://example/o1')
          ),
          RDF::URI('http://example/p'),
          RDF::URI('http://example/o')
        ),
        output: %({
         "@context": {"ex": "http://example/"},
         "@id": {
           "@id": "ex:s1",
           "ex:p1": {"@id": "ex:o1"}
         },
         "ex:p": {"@id": "ex:o"}
       })
      },
      'subject-iib': {
        input: RDF::Statement(
          RDF::Statement(
            RDF::URI('http://example/s1'),
            RDF::URI('http://example/p1'),
            RDF::Node.new('o1')
          ),
          RDF::URI('http://example/p'),
          RDF::URI('http://example/o')
        ),
        output: %({
          "@context": {"ex": "http://example/"},
          "@id": {
            "@id": "ex:s1",
            "ex:p1": {"@id": "_:o1"}
          },
          "ex:p": {"@id": "ex:o"}
        })
      },
      'subject-iil': {
        input: RDF::Statement(
          RDF::Statement(
            RDF::URI('http://example/s1'),
            RDF::URI('http://example/p1'),
            RDF::Literal('o1')
          ),
          RDF::URI('http://example/p'),
          RDF::URI('http://example/o')
        ),
        output: %({
          "@context": {"ex": "http://example/"},
          "@id": {
            "@id": "ex:s1",
            "ex:p1": "o1"
          },
          "ex:p": {"@id": "ex:o"}
        })
      },
      'subject-bii': {
        input: RDF::Statement(
          RDF::Statement(
            RDF::Node('s1'),
            RDF::URI('http://example/p1'),
            RDF::URI('http://example/o1')
          ),
          RDF::URI('http://example/p'),
          RDF::URI('http://example/o')
        ),
        output: %({
          "@context": {"ex": "http://example/"},
          "@id": {
            "@id": "_:s1",
            "ex:p1": {"@id": "ex:o1"}
          },
          "ex:p": {"@id": "ex:o"}
        })
      },
      'subject-bib': {
        input: RDF::Statement(
          RDF::Statement(
            RDF::Node('s1'),
            RDF::URI('http://example/p1'),
            RDF::Node.new('o1')
          ),
          RDF::URI('http://example/p'), RDF::URI('http://example/o')
        ),
        output: %({
          "@context": {"ex": "http://example/"},
          "@id": {
            "@id": "_:s1",
            "ex:p1": {"@id": "_:o1"}
          },
          "ex:p": {"@id": "ex:o"}
        })
      },
      'subject-bil': {
        input: RDF::Statement(
          RDF::Statement(
            RDF::Node('s1'),
            RDF::URI('http://example/p1'),
            RDF::Literal('o1')
          ),
          RDF::URI('http://example/p'),
          RDF::URI('http://example/o')
        ),
        output: %({
          "@context": {"ex": "http://example/"},
          "@id": {
            "@id": "_:s1",
            "ex:p1": "o1"
          },
          "ex:p": {"@id": "ex:o"}
        })
      },
      'object-iii': {
        input: RDF::Statement(
          RDF::URI('http://example/s'),
          RDF::URI('http://example/p'),
          RDF::Statement(
            RDF::URI('http://example/s1'),
            RDF::URI('http://example/p1'),
            RDF::URI('http://example/o1')
          )
        ),
        output: %({
          "@context": {"ex": "http://example/"},
          "@id": "ex:s",
          "ex:p": {
            "@id": {
              "@id": "ex:s1",
              "ex:p1": {"@id": "ex:o1"}
            }
          }
        })
      },
      'object-iib': {
        input: RDF::Statement(
          RDF::URI('http://example/s'),
          RDF::URI('http://example/p'),
          RDF::Statement(
            RDF::URI('http://example/s1'),
            RDF::URI('http://example/p1'),
            RDF::Node.new('o1')
          )
        ),
        output: %({
          "@context": {"ex": "http://example/"},
          "@id": "ex:s",
          "ex:p": {
            "@id": {
              "@id": "ex:s1",
              "ex:p1": {"@id": "_:o1"}
            }
          }
        })
      },
      'object-iil': {
        input: RDF::Statement(
          RDF::URI('http://example/s'),
          RDF::URI('http://example/p'),
          RDF::Statement(
            RDF::URI('http://example/s1'),
            RDF::URI('http://example/p1'),
            RDF::Literal('o1')
          )
        ),
        output: %({
          "@context": {"ex": "http://example/"},
          "@id": "ex:s",
          "ex:p": {
            "@id": {
              "@id": "ex:s1",
              "ex:p1": "o1"
            }
          }
        })
      },
      'recursive-subject': {
        input: RDF::Statement(
          RDF::Statement(
            RDF::Statement(
              RDF::URI('http://example/s2'),
              RDF::URI('http://example/p2'),
              RDF::URI('http://example/o2')
            ),
            RDF::URI('http://example/p1'),
            RDF::URI('http://example/o1')
          ),
          RDF::URI('http://example/p'),
          RDF::URI('http://example/o')
        ),
        output: %({
          "@context": {"ex": "http://example/"},
          "@id": {
            "@id": {
              "@id": "ex:s2",
              "ex:p2": {"@id": "ex:o2"}
            },
            "ex:p1": {"@id": "ex:o1"}
          },
          "ex:p": {"@id": "ex:o"}
        })
      }
    }.each do |name, params|
      it name do
        graph = RDF::Graph.new { |g| g << params[:input] }
        expect(
          serialize(graph, rdfstar: true, prefixes: { ex: 'http://example/' })
        ).to produce_jsonld(JSON.parse(params[:output]), logger)
      end
    end
  end

  unless ENV['CI']
    context "Writes fromRdf tests to isomorphic graph" do
      require 'suite_helper'
      m = Fixtures::SuiteTest::Manifest.open("#{Fixtures::SuiteTest::SUITE}fromRdf-manifest.jsonld")
      describe m.name do
        m.entries.each do |t|
          next unless t.positiveTest? && !t.property('input').include?('0016')

          specify "#{t.property('@id')}: #{t.name}" do
            logger.info "test: #{t.inspect}"
            logger.info "source: #{t.input}"
            t.logger = logger
            pending "Shared list BNode in different graphs" if t.property('input').include?("fromRdf-0021")
            repo = RDF::Repository.load(t.input_loc, format: :nquads)
            jsonld = described_class.buffer(logger: t.logger, **t.options) do |writer|
              writer << repo
            end

            # And then, re-generate jsonld as RDF

            expect(parse(jsonld, format: :jsonld, **t.options)).to be_equivalent_graph(repo, t)
          end
        end
      end
    end
  end

  def parse(input, format: :trig, **options)
    reader = RDF::Reader.for(format)
    RDF::Repository.new << reader.new(input, **options)
  end

  # Serialize ntstr to a string and compare against regexps
  def serialize(ntstr, **options)
    g = ntstr.is_a?(String) ? parse(ntstr, **options) : ntstr
    # logger.info g.dump(:ttl)
    result = JSON::LD::Writer.buffer(logger: logger, **options) do |writer|
      writer << g
    end
    if $verbose
      # puts hash.to_json
    end

    JSON.parse(result)
  end
end
