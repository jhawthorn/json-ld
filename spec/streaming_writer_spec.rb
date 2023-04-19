require_relative 'spec_helper'
require 'rdf/spec/writer'
require 'json/ld/streaming_writer'

describe JSON::LD::StreamingWriter do
  let(:logger) { RDF::Spec.logger }

  after { |example| puts logger if example.exception }

  it_behaves_like 'an RDF::Writer' do
    let(:writer) { JSON::LD::Writer.new(StringIO.new(""), stream: true) }
  end

  context "simple tests" do
    it "uses full URIs without base" do
      input = %(<http://a/b> <http://a/c> <http://a/d> .)
      obj = serialize(input)
      expect(parse(obj.to_json, format: :jsonld)).to be_equivalent_graph(parse(input), logger: logger)
      expect(obj).to produce_jsonld([{
        '@id' => "http://a/b",
        "http://a/c" => [{ "@id" => "http://a/d" }]
      }], logger)
    end

    it "writes multiple kinds of statements" do
      input = %(
        <https://senet.org/gm> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://vocab.org/frbr/core#Work> .
        <https://senet.org/gm> <http://purl.org/dc/terms/title> "Rhythm Paradise"@en .
        <https://senet.org/gm> <https://senet.org/ns#unofficialTitle> "Rhythm Tengoku"@en .
        <https://senet.org/gm> <https://senet.org/ns#urlkey> "rhythm-tengoku" .
      )
      obj = serialize(input)
      expect(parse(obj.to_json, format: :jsonld)).to be_equivalent_graph(parse(input), logger: logger)
      expect(obj).to eql JSON.parse(%([{
        "@id": "https://senet.org/gm",
        "@type": ["http://vocab.org/frbr/core#Work"],
        "http://purl.org/dc/terms/title": [{"@value": "Rhythm Paradise", "@language": "en"}],
        "https://senet.org/ns#unofficialTitle": [{"@value": "Rhythm Tengoku", "@language": "en"}],
        "https://senet.org/ns#urlkey": [{"@value": "rhythm-tengoku"}]
      }]))
    end

    it "serializes multiple subjects" do
      input = '
        @prefix : <http://www.w3.org/2006/03/test-description#> .
        @prefix dc: <http://purl.org/dc/terms/> .
        <http://example.com/test-cases/0001> a :TestCase .
        <http://example.com/test-cases/0002> a :TestCase .
      '
      obj = serialize(input)
      expect(parse(obj.to_json, format: :jsonld)).to be_equivalent_graph(parse(input), logger: logger)
      expect(obj).to match_array(JSON.parse(%([
        {"@id": "http://example.com/test-cases/0001", "@type": ["http://www.w3.org/2006/03/test-description#TestCase"]},
        {"@id": "http://example.com/test-cases/0002", "@type": ["http://www.w3.org/2006/03/test-description#TestCase"]}
      ])))
    end
  end

  context "Named Graphs" do
    {
      "default" => [
        '{<a> <b> <c> .}',
        '[{"@id": "a", "b": [{"@id": "c"}]}]'
      ],
      "named" => [
        '<C> {<a> <b> <c> .}',
        '[{"@id" :  "C", "@graph" :  [{"@id": "a", "b": [{"@id": "c"}]}]}]'
      ],
      "combo" => [
        '
          <a> <b> <c> .
          <C> {<A> <b> <c> .}
        ',
        '[
          {"@id": "a", "b": [{"@id": "c"}]},
          {"@id": "C", "@graph": [{"@id": "A", "b": [{"@id": "c"}]}]}
        ]'
      ],
      "combo with duplicated statement" => [
        '
          <a> <b> <c> .
          <C> {<a> <b> <c> .}
        ',
        '[
          {"@id": "a", "b": [{"@id": "c"}]},
          {"@id": "C", "@graph": [{"@id": "a", "b": [{"@id": "c"}]}]}
        ]'
      ]
    }.each_pair do |title, (input, matches)|
      context title do
        subject { serialize(input) }

        it "matches expected json" do
          expect(subject).to match_array(JSON.parse(matches))
        end
      end
    end
  end

  unless ENV['CI']
    context "Writes fromRdf tests to isomorphic graph" do
      require 'suite_helper'
      m = Fixtures::SuiteTest::Manifest.open("#{Fixtures::SuiteTest::SUITE}fromRdf-manifest.jsonld")
      [nil, {}].each do |ctx|
        context "with context #{ctx.inspect}" do
          describe m.name do
            m.entries.each do |t|
              next unless t.positiveTest? && !t.property('input').include?('0016')

              t.logger = RDF::Spec.logger
              t.logger.info "test: #{t.inspect}"
              t.logger.info "source: #{t.input}"
              specify "#{t.property('@id')}: #{t.name}" do
                repo = RDF::Repository.load(t.input_loc, format: :nquads)
                jsonld = JSON::LD::Writer.buffer(stream: true, context: ctx, logger: t.logger, **t.options) do |writer|
                  writer << repo
                end
                t.logger.info "Generated: #{jsonld}"

                # And then, re-generate jsonld as RDF
                expect(parse(jsonld, format: :jsonld, **t.options)).to be_equivalent_graph(repo, t)
              end
            end
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
    logger = RDF::Spec.logger
    logger.info(g.dump(:ttl))
    result = JSON::LD::Writer.buffer(logger: logger, stream: true, **options) do |writer|
      writer << g
    end
    puts result if $verbose

    JSON.parse(result)
  end
end
