# frozen_string_literal: true

require_relative 'spec_helper'

describe JSON::LD::API do
  let(:logger) { RDF::Spec.logger }

  describe ".expand" do
    {
      'empty doc': {
        input: {},
        output: []
      },
      '@list coercion': {
        input: %({
          "@context": {
            "foo": {"@id": "http://example.com/foo", "@container": "@list"}
          },
          "foo": [{"@value": "bar"}]
        }),
        output: %([{
          "http://example.com/foo": [{"@list": [{"@value": "bar"}]}]
        }])
      },
      'native values in list': {
        input: %({
          "http://example.com/foo": {"@list": [1, 2]}
        }),
        output: %([{
          "http://example.com/foo": [{"@list": [{"@value": 1}, {"@value": 2}]}]
        }])
      },
      '@graph': {
        input: %({
          "@context": {"ex": "http://example.com/"},
          "@graph": [
            {"ex:foo": {"@value": "foo"}},
            {"ex:bar": {"@value": "bar"}}
          ]
        }),
        output: %([
          {"http://example.com/foo": [{"@value": "foo"}]},
          {"http://example.com/bar": [{"@value": "bar"}]}
        ])
      },
      '@graph value (expands to array form)': {
        input: %({
          "@context": {"ex": "http://example.com/"},
          "ex:p": {
            "@id": "ex:Sub1",
            "@graph": {
              "ex:q": "foo"
            }
          }
        }),
        output: %([{
          "http://example.com/p": [{
            "@id": "http://example.com/Sub1",
            "@graph": [{
              "http://example.com/q": [{"@value": "foo"}]
            }]
          }]
        }])
      },
      '@type with CURIE': {
        input: %({
          "@context": {"ex": "http://example.com/"},
          "@type": "ex:type"
        }),
        output: %([
          {"@type": ["http://example.com/type"]}
        ])
      },
      '@type with CURIE and muliple values': {
        input: %({
          "@context": {"ex": "http://example.com/"},
          "@type": ["ex:type1", "ex:type2"]
        }),
        output: %([
          {"@type": ["http://example.com/type1", "http://example.com/type2"]}
        ])
      },
      '@value with false': {
        input: %({"http://example.com/ex": {"@value": false}}),
        output: %([{"http://example.com/ex": [{"@value": false}]}])
      },
      'compact IRI': {
        input: %({
          "@context": {"ex": "http://example.com/"},
          "ex:p": {"@id": "ex:Sub1"}
        }),
        output: %([{
          "http://example.com/p": [{"@id": "http://example.com/Sub1"}]
        }])
      }
    }.each_pair do |title, params|
      it(title) { run_expand params }
    end

    context "default language" do
      {
        base: {
          input: %({
            "http://example/foo": "bar"
          }),
          output: %([{
            "http://example/foo": [{"@value": "bar", "@language": "en"}]
          }]),
          language: "en"
        },
        override: {
          input: %({
            "@context": {"@language": null},
            "http://example/foo": "bar"
          }),
          output: %([{
            "http://example/foo": [{"@value": "bar"}]
          }]),
          language: "en"
        }
      }.each_pair do |title, params|
        it(title) { run_expand params }
      end
    end

    context "with relative IRIs" do
      {
        base: {
          input: %({
            "@id": "",
            "@type": "http://www.w3.org/2000/01/rdf-schema#Resource"
          }),
          output: %([{
            "@id": "http://example.org/",
            "@type": ["http://www.w3.org/2000/01/rdf-schema#Resource"]
          }])
        },
        relative: {
          input: %({
            "@id": "a/b",
            "@type": "http://www.w3.org/2000/01/rdf-schema#Resource"
          }),
          output: %([{
            "@id": "http://example.org/a/b",
            "@type": ["http://www.w3.org/2000/01/rdf-schema#Resource"]
          }])
        },
        hash: {
          input: %({
            "@id": "#a",
            "@type": "http://www.w3.org/2000/01/rdf-schema#Resource"
          }),
          output: %([{
            "@id": "http://example.org/#a",
            "@type": ["http://www.w3.org/2000/01/rdf-schema#Resource"]
          }])
        },
        'unmapped @id': {
          input: %({
            "http://example.com/foo": {"@id": "bar"}
          }),
          output: %([{
            "http://example.com/foo": [{"@id": "http://example.org/bar"}]
          }])
        },
        'json-ld-syntax#66': {
          input: %({
            "@context": {
              "@base": "https://ex.org/",
              "u": {"@id": "urn:u:", "@type": "@id"}
            },
            "u": ["#Test", "#Test:2"]
          }),
          output: %([{
            "urn:u:": [
              {"@id": "https://ex.org/#Test"},
              {"@id": "https://ex.org/#Test:2"}
            ]
          }])
        }
      }.each do |title, params|
        it(title) { run_expand params.merge(base: "http://example.org/") }
      end
    end

    context "with relative property IRIs" do
      {
        base: {
          input: %({
            "http://a/b": "foo"
          }),
          output: %([{
            "http://a/b": [{"@value": "foo"}]
          }])
        },
        relative: {
          input: %({
            "a/b": "foo"
          }),
          output: %([])
        },
        hash: {
          input: %({
            "#a": "foo"
          }),
          output: %([])
        },
        dotseg: {
          input: %({
            "../a": "foo"
          }),
          output: %([])
        }
      }.each do |title, params|
        it(title) { run_expand params.merge(base: "http://example.org/") }
      end

      context "with @vocab" do
        {
          base: {
            input: %({
              "@context": {"@vocab": "http://vocab/"},
              "http://a/b": "foo"
            }),
            output: %([{
              "http://a/b": [{"@value": "foo"}]
            }])
          },
          relative: {
            input: %({
              "@context": {"@vocab": "http://vocab/"},
              "a/b": "foo"
            }),
            output: %([{
              "http://vocab/a/b": [{"@value": "foo"}]
            }])
          },
          hash: {
            input: %({
              "@context": {"@vocab": "http://vocab/"},
              "#a": "foo"
            }),
            output: %([{
              "http://vocab/#a": [{"@value": "foo"}]
            }])
          },
          dotseg: {
            input: %({
              "@context": {"@vocab": "http://vocab/"},
              "../a": "foo"
            }),
            output: %([{
              "http://vocab/../a": [{"@value": "foo"}]
            }])
          }
        }.each do |title, params|
          it(title) { run_expand params.merge(base: "http://example.org/") }
        end
      end

      context "with @vocab: ''" do
        {
          base: {
            input: %({
              "@context": {"@vocab": ""},
              "http://a/b": "foo"
            }),
            output: %([{
              "http://a/b": [{"@value": "foo"}]
            }])
          },
          relative: {
            input: %({
              "@context": {"@vocab": ""},
              "a/b": "foo"
            }),
            output: %([{
              "http://example.org/a/b": [{"@value": "foo"}]
            }])
          },
          hash: {
            input: %({
              "@context": {"@vocab": ""},
              "#a": "foo"
            }),
            output: %([{
              "http://example.org/#a": [{"@value": "foo"}]
            }])
          },
          dotseg: {
            input: %({
              "@context": {"@vocab": ""},
              "../a": "foo"
            }),
            output: %([{
              "http://example.org/../a": [{"@value": "foo"}]
            }])
          },
          example: {
            input: %({
              "@context": {
                "@base": "http://example/document",
                "@vocab": ""
              },
              "@id": "http://example.org/places#BrewEats",
              "@type": "#Restaurant",
              "#name": "Brew Eats"
            }),
            output: %([{
              "@id": "http://example.org/places#BrewEats",
              "@type": ["http://example/document#Restaurant"],
              "http://example/document#name": [{"@value": "Brew Eats"}]
            }])
          }
        }.each do |title, params|
          it(title) { run_expand params.merge(base: "http://example.org/") }
        end
      end

      context "with @vocab: '/relative#'" do
        {
          base: {
            input: %({
              "@context": {"@vocab": "/relative#"},
              "http://a/b": "foo"
            }),
            output: %([{
              "http://a/b": [{"@value": "foo"}]
            }])
          },
          relative: {
            input: %({
              "@context": {"@vocab": "/relative#"},
              "a/b": "foo"
            }),
            output: %([{
              "http://example.org/relative#a/b": [{"@value": "foo"}]
            }])
          },
          hash: {
            input: %({
              "@context": {"@vocab": "/relative#"},
              "#a": "foo"
            }),
            output: %([{
              "http://example.org/relative##a": [{"@value": "foo"}]
            }])
          },
          dotseg: {
            input: %({
              "@context": {"@vocab": "/relative#"},
              "../a": "foo"
            }),
            output: %([{
              "http://example.org/relative#../a": [{"@value": "foo"}]
            }])
          },
          example: {
            input: %({
              "@context": {
                "@base": "http://example/document",
                "@vocab": "/relative#"
              },
              "@id": "http://example.org/places#BrewEats",
              "@type": "Restaurant",
              "name": "Brew Eats"
            }),
            output: %([{
              "@id": "http://example.org/places#BrewEats",
              "@type": ["http://example/relative#Restaurant"],
              "http://example/relative#name": [{"@value": "Brew Eats"}]
            }])
          }
        }.each do |title, params|
          it(title) { run_expand params.merge(base: "http://example.org/") }
        end
      end
    end

    context "keyword aliasing" do
      {
        '@id': {
          input: %({
            "@context": {"id": "@id"},
            "id": "",
            "@type": "http://www.w3.org/2000/01/rdf-schema#Resource"
          }),
          output: %([{
            "@id": "",
            "@type":[ "http://www.w3.org/2000/01/rdf-schema#Resource"]
          }])
        },
        '@type': {
          input: %({
            "@context": {"type": "@type"},
            "type": "http://www.w3.org/2000/01/rdf-schema#Resource",
            "http://example.com/foo": {"@value": "bar", "type": "http://example.com/baz"}
          }),
          output: %([{
            "@type": ["http://www.w3.org/2000/01/rdf-schema#Resource"],
            "http://example.com/foo": [{"@value": "bar", "@type": "http://example.com/baz"}]
          }])
        },
        '@language': {
          input: %({
            "@context": {"language": "@language"},
            "http://example.com/foo": {"@value": "bar", "language": "baz"}
          }),
          output: %([{
            "http://example.com/foo": [{"@value": "bar", "@language": "baz"}]
          }])
        },
        '@value': {
          input: %({
            "@context": {"literal": "@value"},
            "http://example.com/foo": {"literal": "bar"}
          }),
          output: %([{
            "http://example.com/foo": [{"@value": "bar"}]
          }])
        },
        '@list': {
          input: %({
            "@context": {"list": "@list"},
            "http://example.com/foo": {"list": ["bar"]}
          }),
          output: %([{
            "http://example.com/foo": [{"@list": [{"@value": "bar"}]}]
          }])
        }
      }.each do |title, params|
        it(title) { run_expand params }
      end
    end

    context "native types" do
      {
        true => {
          input: %({
            "@context": {"e": "http://example.org/vocab#"},
            "e:bool": true
          }),
          output: %([{
            "http://example.org/vocab#bool": [{"@value": true}]
          }])
        },
        false => {
          input: %({
            "@context": {"e": "http://example.org/vocab#"},
            "e:bool": false
          }),
          output: %([{
            "http://example.org/vocab#bool": [{"@value": false}]
          }])
        },
        double: {
          input: %({
            "@context": {"e": "http://example.org/vocab#"},
            "e:double": 1.23
          }),
          output: %([{
            "http://example.org/vocab#double": [{"@value": 1.23}]
          }])
        },
        'double-zero': {
          input: %({
            "@context": {"e": "http://example.org/vocab#"},
            "e:double-zero": 0.0e0
          }),
          output: %([{
            "http://example.org/vocab#double-zero": [{"@value": 0.0e0}]
          }])
        },
        integer: {
          input: %({
            "@context": {"e": "http://example.org/vocab#"},
            "e:integer": 123
          }),
          output: %([{
            "http://example.org/vocab#integer": [{"@value": 123}]
          }])
        }
      }.each do |title, params|
        it(title) { run_expand params }
      end

      context "with @type: @none" do
        {
          true => {
            input: %({
              "@context": {"e": {"@id": "http://example.org/vocab#bool", "@type": "@none"}},
              "e": true
            }),
            output: %( [{
              "http://example.org/vocab#bool": [{"@value": true}]
            }])
          },
          false => {
            input: %({
              "@context": {"e": {"@id": "http://example.org/vocab#bool", "@type": "@none"}},
              "e": false
            }),
            output: %([{
              "http://example.org/vocab#bool": [{"@value": false}]
            }])
          },
          double: {
            input: %({
              "@context": {"e": {"@id": "http://example.org/vocab#double", "@type": "@none"}},
              "e": 1.23
            }),
            output: %([{
              "http://example.org/vocab#double": [{"@value": 1.23}]
            }])
          },
          'double-zero': {
            input: %({
              "@context": {"e": {"@id": "http://example.org/vocab#double", "@type": "@none"}},
              "e": 0.0e0
            }),
            output: %([{
              "http://example.org/vocab#double": [{"@value": 0.0e0}]
            }])
          },
          integer: {
            input: %({
              "@context": {"e": {"@id": "http://example.org/vocab#integer", "@type": "@none"}},
              "e": 123
            }),
            output: %([{
              "http://example.org/vocab#integer": [{"@value": 123}]
            }])
          }
        }.each do |title, params|
          it(title) { run_expand(processingMode: "json-ld-1.1", **params) }
        end
      end

      context "with @type: @id" do
        {
          true => {
            input: %({
              "@context": {"e": {"@id": "http://example.org/vocab#bool", "@type": "@id"}},
              "e": true
            }),
            output: %( [{
              "http://example.org/vocab#bool": [{"@value": true}]
            }])
          },
          false => {
            input: %({
              "@context": {"e": {"@id": "http://example.org/vocab#bool", "@type": "@id"}},
              "e": false
            }),
            output: %([{
              "http://example.org/vocab#bool": [{"@value": false}]
            }])
          },
          double: {
            input: %({
              "@context": {"e": {"@id": "http://example.org/vocab#double", "@type": "@id"}},
              "e": 1.23
            }),
            output: %([{
              "http://example.org/vocab#double": [{"@value": 1.23}]
            }])
          },
          'double-zero': {
            input: %({
              "@context": {"e": {"@id": "http://example.org/vocab#double", "@type": "@id"}},
              "e": 0.0e0
            }),
            output: %([{
              "http://example.org/vocab#double": [{"@value": 0.0e0}]
            }])
          },
          integer: {
            input: %({
              "@context": {"e": {"@id": "http://example.org/vocab#integer", "@type": "@id"}},
              "e": 123
            }),
            output: %([{
              "http://example.org/vocab#integer": [{"@value": 123}]
            }])
          }
        }.each do |title, params|
          it(title) { run_expand params }
        end
      end

      context "with @type: @vocab" do
        {
          true => {
            input: %({
              "@context": {"e": {"@id": "http://example.org/vocab#bool", "@type": "@vocab"}},
              "e": true
            }),
            output: %( [{
              "http://example.org/vocab#bool": [{"@value": true}]
            }])
          },
          false => {
            input: %({
              "@context": {"e": {"@id": "http://example.org/vocab#bool", "@type": "@vocab"}},
              "e": false
            }),
            output: %([{
              "http://example.org/vocab#bool": [{"@value": false}]
            }])
          },
          double: {
            input: %({
              "@context": {"e": {"@id": "http://example.org/vocab#double", "@type": "@vocab"}},
              "e": 1.23
            }),
            output: %([{
              "http://example.org/vocab#double": [{"@value": 1.23}]
            }])
          },
          'double-zero': {
            input: %({
              "@context": {"e": {"@id": "http://example.org/vocab#double", "@type": "@vocab"}},
              "e": 0.0e0
            }),
            output: %([{
              "http://example.org/vocab#double": [{"@value": 0.0e0}]
            }])
          },
          integer: {
            input: %({
              "@context": {"e": {"@id": "http://example.org/vocab#integer", "@type": "@vocab"}},
              "e": 123
            }),
            output: %([{
              "http://example.org/vocab#integer": [{"@value": 123}]
            }])
          }
        }.each do |title, params|
          it(title) { run_expand params }
        end
      end
    end

    context "with @type: @json" do
      {
        true => {
          input: %({
            "@context": {
              "@version": 1.1,
              "e": {"@id": "http://example.org/vocab#bool", "@type": "@json"}
            },
            "e": true
          }),
          output: %( [{
            "http://example.org/vocab#bool": [{"@value": true, "@type": "@json"}]
          }])
        },
        false => {
          input: %({
            "@context": {
              "@version": 1.1,
              "e": {"@id": "http://example.org/vocab#bool", "@type": "@json"}
            },
            "e": false
          }),
          output: %([{
            "http://example.org/vocab#bool": [{"@value": false, "@type": "@json"}]
          }])
        },
        double: {
          input: %({
            "@context": {
              "@version": 1.1,
              "e": {"@id": "http://example.org/vocab#double", "@type": "@json"}
            },
            "e": 1.23
          }),
          output: %([{
            "http://example.org/vocab#double": [{"@value": 1.23, "@type": "@json"}]
          }])
        },
        'double-zero': {
          input: %({
            "@context": {
              "@version": 1.1,
              "e": {"@id": "http://example.org/vocab#double", "@type": "@json"}
            },
            "e": 0.0e0
          }),
          output: %([{
            "http://example.org/vocab#double": [{"@value": 0.0e0, "@type": "@json"}]
          }])
        },
        integer: {
          input: %({
            "@context": {
              "@version": 1.1,
              "e": {"@id": "http://example.org/vocab#integer", "@type": "@json"}
            },
            "e": 123
          }),
          output: %([{
            "http://example.org/vocab#integer": [{"@value": 123, "@type": "@json"}]
          }])
        },
        string: {
          input: %({
            "@context": {
              "@version": 1.1,
              "e": {"@id": "http://example.org/vocab#string", "@type": "@json"}
            },
            "e": "string"
          }),
          output: %([{
            "http://example.org/vocab#string": [{
              "@value": "string",
              "@type": "@json"
            }]
          }])
        },
        null: {
          input: %({
            "@context": {
              "@version": 1.1,
              "e": {"@id": "http://example.org/vocab#null", "@type": "@json"}
            },
            "e": null
          }),
          output: %([{
            "http://example.org/vocab#null": [{
              "@value": null,
              "@type": "@json"
            }]
          }])
        },
        object: {
          input: %({
            "@context": {
              "@version": 1.1,
              "e": {"@id": "http://example.org/vocab#object", "@type": "@json"}
            },
            "e": {"foo": "bar"}
          }),
          output: %([{
            "http://example.org/vocab#object": [{"@value": {"foo": "bar"}, "@type": "@json"}]
          }])
        },
        array: {
          input: %({
            "@context": {
              "@version": 1.1,
              "e": {"@id": "http://example.org/vocab#array", "@type": "@json"}
            },
            "e": [{"foo": "bar"}]
          }),
          output: %([{
            "http://example.org/vocab#array": [{"@value": [{"foo": "bar"}], "@type": "@json"}]
          }])
        },
        'Does not expand terms inside json': {
          input: %({
            "@context": {
              "@version": 1.1,
              "e": {"@id": "http://example.org/vocab#array", "@type": "@json"}
            },
            "e": [{"e": "bar"}]
          }),
          output: %([{
            "http://example.org/vocab#array": [{"@value": [{"e": "bar"}], "@type": "@json"}]
          }])
        },
        'Already expanded object': {
          input: %({
            "http://example.org/vocab#object": [{"@value": {"foo": "bar"}, "@type": "@json"}]
          }),
          output: %([{
            "http://example.org/vocab#object": [{"@value": {"foo": "bar"}, "@type": "@json"}]
          }]),
          processingMode: 'json-ld-1.1'
        },
        'Already expanded object with aliased keys': {
          input: %({
            "@context": {"@version": 1.1, "value": "@value", "type": "@type", "json": "@json"},
            "http://example.org/vocab#object": [{"value": {"foo": "bar"}, "type": "json"}]
          }),
          output: %([{
            "http://example.org/vocab#object": [{"@value": {"foo": "bar"}, "@type": "@json"}]
          }])
        }
      }.each do |title, params|
        it(title) { run_expand params }
      end
    end

    context "coerced typed values" do
      {
        boolean: {
          input: %({
            "@context": {"foo": {"@id": "http://example.org/foo", "@type": "http://www.w3.org/2001/XMLSchema#boolean"}},
            "foo": "true"
          }),
          output: %([{
            "http://example.org/foo": [{"@value": "true", "@type": "http://www.w3.org/2001/XMLSchema#boolean"}]
          }])
        },
        date: {
          input: %({
            "@context": {"foo": {"@id": "http://example.org/foo", "@type": "http://www.w3.org/2001/XMLSchema#date"}},
            "foo": "2011-03-26"
          }),
          output: %([{
            "http://example.org/foo": [{"@value": "2011-03-26", "@type": "http://www.w3.org/2001/XMLSchema#date"}]
          }])
        }
      }.each do |title, params|
        it(title) { run_expand params }
      end
    end

    context "null" do
      {
        value: {
          input: %({"http://example.com/foo": null}),
          output: []
        },
        '@value': {
          input: %({"http://example.com/foo": {"@value": null}}),
          output: []
        },
        '@value and non-null @type': {
          input: %({"http://example.com/foo": {"@value": null, "@type": "http://type"}}),
          output: []
        },
        '@value and non-null @language': {
          input: %({"http://example.com/foo": {"@value": null, "@language": "en"}}),
          output: []
        },
        'array with null elements': {
          input: %({"http://example.com/foo": [null]}),
          output: %([{"http://example.com/foo": []}])
        },
        '@set with null @value': {
          input: %({
            "http://example.com/foo": [
              {"@value": null, "@type": "http://example.org/Type"}
            ]
          }),
          output: %([{
            "http://example.com/foo": []
          }])
        }
      }.each do |title, params|
        it(title) { run_expand params }
      end
    end

    context "@direction" do
      {
        'value with coerced null direction': {
          input: %({
            "@context": {
              "@direction": "rtl",
              "ex": "http://example.org/vocab#",
              "ex:ltr": { "@direction": "ltr" },
              "ex:none": { "@direction": null }
            },
            "ex:rtl": "rtl",
            "ex:ltr": "ltr",
            "ex:none": "no direction"
          }),
          output: %([
            {
              "http://example.org/vocab#rtl": [{"@value": "rtl", "@direction": "rtl"}],
              "http://example.org/vocab#ltr": [{"@value": "ltr", "@direction": "ltr"}],
              "http://example.org/vocab#none": [{"@value": "no direction"}]
            }
          ])
        }
      }.each_pair do |title, params|
        it(title) { run_expand params }
      end
    end

    context "default language" do
      {
        'value with coerced null language': {
          input: %({
            "@context": {
              "@language": "en",
              "ex": "http://example.org/vocab#",
              "ex:german": { "@language": "de" },
              "ex:nolang": { "@language": null }
            },
            "ex:german": "german",
            "ex:nolang": "no language"
          }),
          output: %([
            {
              "http://example.org/vocab#german": [{"@value": "german", "@language": "de"}],
              "http://example.org/vocab#nolang": [{"@value": "no language"}]
            }
          ])
        }
      }.each do |title, params|
        it(title) { run_expand params }
      end

      context "and default direction" do
        {
          'value with coerced null direction': {
            input: %({
              "@context": {
                "@language": "en",
                "@direction": "rtl",
                "ex": "http://example.org/vocab#",
                "ex:ltr": { "@direction": "ltr" },
                "ex:none": { "@direction": null },
                "ex:german": { "@language": "de" },
                "ex:nolang": { "@language": null },
                "ex:german_ltr": { "@language": "de", "@direction": "ltr" },
                "ex:nolang_ltr": { "@language": null, "@direction": "ltr" },
                "ex:none_none": { "@language": null, "@direction": null },
                "ex:german_none": { "@language": "de", "@direction": null }
              },
              "ex:rtl": "rtl en",
              "ex:ltr": "ltr en",
              "ex:none": "no direction en",
              "ex:german": "german rtl",
              "ex:nolang": "no language rtl",
              "ex:german_ltr": "german ltr",
              "ex:nolang_ltr": "no language ltr",
              "ex:none_none": "no language or direction",
              "ex:german_none": "german no direction"
            }),
            output: %([
              {
                "http://example.org/vocab#rtl": [{"@value": "rtl en", "@language": "en", "@direction": "rtl"}],
                "http://example.org/vocab#ltr": [{"@value": "ltr en", "@language": "en", "@direction": "ltr"}],
                "http://example.org/vocab#none": [{"@value": "no direction en", "@language": "en"}],
                "http://example.org/vocab#german": [{"@value": "german rtl", "@language": "de", "@direction": "rtl"}],
                "http://example.org/vocab#nolang": [{"@value": "no language rtl", "@direction": "rtl"}],
                "http://example.org/vocab#german_ltr": [{"@value": "german ltr", "@language": "de", "@direction": "ltr"}],
                "http://example.org/vocab#nolang_ltr": [{"@value": "no language ltr", "@direction": "ltr"}],
                "http://example.org/vocab#none_none": [{"@value": "no language or direction"}],
                "http://example.org/vocab#german_none": [{"@value": "german no direction", "@language": "de"}]
              }
            ])
          }
        }.each_pair do |title, params|
          it(title) { run_expand params }
        end
      end
    end

    context "default vocabulary" do
      {
        property: {
          input: %({
            "@context": {"@vocab": "http://example.com/"},
            "verb": {"@value": "foo"}
          }),
          output: %([{
            "http://example.com/verb": [{"@value": "foo"}]
          }])
        },
        datatype: {
          input: %({
            "@context": {"@vocab": "http://example.com/"},
            "http://example.org/verb": {"@value": "foo", "@type": "string"}
          }),
          output: %([{
            "http://example.org/verb": [{"@value": "foo", "@type": "http://example.com/string"}]
          }])
        },
        'expand-0028': {
          input: %({
            "@context": {
              "@vocab": "http://example.org/vocab#",
              "date": { "@type": "dateTime" }
            },
            "@id": "example1",
            "@type": "test",
            "date": "2011-01-25T00:00:00Z",
            "embed": {
              "@id": "example2",
              "expandedDate": { "@value": "2012-08-01T00:00:00Z", "@type": "dateTime" }
            }
          }),
          output: %([
            {
              "@id": "http://foo/bar/example1",
              "@type": ["http://example.org/vocab#test"],
              "http://example.org/vocab#date": [
                {
                  "@value": "2011-01-25T00:00:00Z",
                  "@type": "http://example.org/vocab#dateTime"
                }
              ],
              "http://example.org/vocab#embed": [
                {
                  "@id": "http://foo/bar/example2",
                  "http://example.org/vocab#expandedDate": [
                    {
                      "@value": "2012-08-01T00:00:00Z",
                      "@type": "http://example.org/vocab#dateTime"
                    }
                  ]
                }
              ]
            }
          ])
        }
      }.each do |title, params|
        it(title) { run_expand params.merge(base: "http://foo/bar/") }
      end
    end

    context "unmapped properties" do
      {
        'unmapped key': {
          input: %({"foo": "bar"}),
          output: []
        },
        'unmapped @type as datatype': {
          input: %({
            "http://example.com/foo": {"@value": "bar", "@type": "baz"}
          }),
          output: %([{
            "http://example.com/foo": [{"@value": "bar", "@type": "http://example/baz"}]
          }])
        },
        'unknown keyword': {
          input: %({"@foo": "bar"}),
          output: []
        },
        value: {
          input: %({
            "@context": {"ex": {"@id": "http://example.org/idrange", "@type": "@id"}},
            "@id": "http://example.org/Subj",
            "idrange": "unmapped"
          }),
          output: []
        },
        'context reset': {
          input: %({
            "@context": {"ex": "http://example.org/", "prop": "ex:prop"},
            "@id": "http://example.org/id1",
            "prop": "prop",
            "ex:chain": {
              "@context": null,
              "@id": "http://example.org/id2",
              "prop": "prop"
            }
          }),
          output: %([{
            "@id": "http://example.org/id1",
            "http://example.org/prop": [{"@value": "prop"}],
            "http://example.org/chain": [{"@id": "http://example.org/id2"}]
          }])
        }
      }.each do |title, params|
        it(title) { run_expand params.merge(base: "http://example/") }
      end
    end

    context "@container: @index" do
      {
        'string annotation': {
          input: %({
            "@context": {
              "container": {
                "@id": "http://example.com/container",
                "@container": "@index"
              }
            },
            "@id": "http://example.com/annotationsTest",
            "container": {
              "en": "The Queen",
              "de": [ "Die Königin", "Ihre Majestät" ]
            }
          }),
          output: %([{
            "@id": "http://example.com/annotationsTest",
            "http://example.com/container": [
              {"@value": "Die Königin", "@index": "de"},
              {"@value": "Ihre Majestät", "@index": "de"},
              {"@value": "The Queen", "@index": "en"}
            ]
          }])
        }
      }.each do |title, params|
        it(title) { run_expand params }
      end

      context "@index: property" do
        {
          'error if @version is json-ld-1.0': {
            input: %({
              "@context": {
                "@vocab": "http://example.com/",
                "container": {"@container": "@index", "@index": "prop"}
              },
              "@id": "http://example.com/annotationsTest",
              "container": {
                "en": "The Queen",
                "de": [ "Die Königin", "Ihre Majestät" ]
              }
            }),
            exception: JSON::LD::JsonLdError::InvalidTermDefinition,
            processingMode: 'json-ld-1.0'
          },
          'error if @container does not include @index': {
            input: %({
              "@context": {
                "@version": 1.1,
                "@vocab": "http://example.com/",
                "container": {"@index": "prop"}
              },
              "@id": "http://example.com/annotationsTest",
              "container": {
                "en": "The Queen",
                "de": [ "Die Königin", "Ihre Majestät" ]
              }
            }),
            exception: JSON::LD::JsonLdError::InvalidTermDefinition
          },
          'error if @index is a keyword': {
            input: %({
              "@context": {
                "@version": 1.1,
                "@vocab": "http://example.com/",
                "container": {
                  "@id": "http://example.com/container",
                  "@container": "@index",
                  "@index": "@index"
                }
              },
              "@id": "http://example.com/annotationsTest",
              "container": {
                "en": "The Queen",
                "de": [ "Die Königin", "Ihre Majestät" ]
              }
            }),
            exception: JSON::LD::JsonLdError::InvalidTermDefinition
          },
          'error if @index is not a string': {
            input: %({
              "@context": {
                "@version": 1.1,
                "@vocab": "http://example.com/",
                "container": {
                  "@id": "http://example.com/container",
                  "@container": "@index",
                  "@index": true
                }
              },
              "@id": "http://example.com/annotationsTest",
              "container": {
                "en": "The Queen",
                "de": [ "Die Königin", "Ihre Majestät" ]
              }
            }),
            exception: JSON::LD::JsonLdError::InvalidTermDefinition
          },
          'error if attempting to add property to value object': {
            input: %({
              "@context": {
                "@version": 1.1,
                "@vocab": "http://example.com/",
                "container": {
                  "@id": "http://example.com/container",
                  "@container": "@index",
                  "@index": "prop"
                }
              },
              "@id": "http://example.com/annotationsTest",
              "container": {
                "en": "The Queen",
                "de": [ "Die Königin", "Ihre Majestät" ]
              }
            }),
            exception: JSON::LD::JsonLdError::InvalidValueObject
          },
          'property-valued index expands to property value, instead of @index (value)': {
            input: %({
              "@context": {
                "@version": 1.1,
                "@base": "http://example.com/",
                "@vocab": "http://example.com/",
                "author": {"@type": "@id", "@container": "@index", "@index": "prop"}
              },
              "@id": "article",
              "author": {
                "regular": "person/1",
                "guest": ["person/2", "person/3"]
              }
            }),
            output: %([{
              "@id": "http://example.com/article",
              "http://example.com/author": [
                {"@id": "http://example.com/person/1", "http://example.com/prop": [{"@value": "regular"}]},
                {"@id": "http://example.com/person/2", "http://example.com/prop": [{"@value": "guest"}]},
                {"@id": "http://example.com/person/3", "http://example.com/prop": [{"@value": "guest"}]}
              ]
            }])
          },
          'property-valued index appends to property value, instead of @index (value)': {
            input: %({
              "@context": {
                "@version": 1.1,
                "@base": "http://example.com/",
                "@vocab": "http://example.com/",
                "author": {"@type": "@id", "@container": "@index", "@index": "prop"}
              },
              "@id": "article",
              "author": {
                "regular": {"@id": "person/1", "http://example.com/prop": "foo"},
                "guest": [
                  {"@id": "person/2", "prop": "foo"},
                  {"@id": "person/3", "prop": "foo"}
                ]
              }
            }),
            output: %([{
              "@id": "http://example.com/article",
              "http://example.com/author": [
                {"@id": "http://example.com/person/1", "http://example.com/prop": [{"@value": "regular"}, {"@value": "foo"}]},
                {"@id": "http://example.com/person/2", "http://example.com/prop": [{"@value": "guest"}, {"@value": "foo"}]},
                {"@id": "http://example.com/person/3", "http://example.com/prop": [{"@value": "guest"}, {"@value": "foo"}]}
              ]
            }])
          },
          'property-valued index expands to property value, instead of @index (node)': {
            input: %({
              "@context": {
                "@version": 1.1,
                "@base": "http://example.com/",
                "@vocab": "http://example.com/",
                "author": {"@type": "@id", "@container": "@index", "@index": "prop"},
                "prop": {"@type": "@vocab"}
              },
              "@id": "http://example.com/article",
              "author": {
                "regular": "person/1",
                "guest": ["person/2", "person/3"]
              }
            }),
            output: %([{
              "@id": "http://example.com/article",
              "http://example.com/author": [
                {"@id": "http://example.com/person/1", "http://example.com/prop": [{"@id": "http://example.com/regular"}]},
                {"@id": "http://example.com/person/2", "http://example.com/prop": [{"@id": "http://example.com/guest"}]},
                {"@id": "http://example.com/person/3", "http://example.com/prop": [{"@id": "http://example.com/guest"}]}
              ]
            }])
          },
          'property-valued index appends to property value, instead of @index (node)': {
            input: %({
              "@context": {
                "@version": 1.1,
                "@base": "http://example.com/",
                "@vocab": "http://example.com/",
                "author": {"@type": "@id", "@container": "@index", "@index": "prop"},
                "prop": {"@type": "@vocab"}
              },
              "@id": "http://example.com/article",
              "author": {
                "regular": {"@id": "person/1", "prop": "foo"},
                "guest": [
                  {"@id": "person/2", "prop": "foo"},
                  {"@id": "person/3", "prop": "foo"}
                ]
              }
            }),
            output: %([{
              "@id": "http://example.com/article",
              "http://example.com/author": [
                {"@id": "http://example.com/person/1", "http://example.com/prop": [{"@id": "http://example.com/regular"}, {"@id": "http://example.com/foo"}]},
                {"@id": "http://example.com/person/2", "http://example.com/prop": [{"@id": "http://example.com/guest"}, {"@id": "http://example.com/foo"}]},
                {"@id": "http://example.com/person/3", "http://example.com/prop": [{"@id": "http://example.com/guest"}, {"@id": "http://example.com/foo"}]}
              ]
            }])
          },
          'property-valued index does not output property for @none': {
            input: %({
              "@context": {
                "@version": 1.1,
                "@base": "http://example.com/",
                "@vocab": "http://example.com/",
                "author": {"@type": "@id", "@container": "@index", "@index": "prop"},
                "prop": {"@type": "@vocab"}
              },
              "@id": "http://example.com/article",
              "author": {
                "@none": {"@id": "person/1"},
                "guest": [
                  {"@id": "person/2"},
                  {"@id": "person/3"}
                ]
              }
            }),
            output: %([{
              "@id": "http://example.com/article",
              "http://example.com/author": [
                {"@id": "http://example.com/person/1"},
                {"@id": "http://example.com/person/2", "http://example.com/prop": [{"@id": "http://example.com/guest"}]},
                {"@id": "http://example.com/person/3", "http://example.com/prop": [{"@id": "http://example.com/guest"}]}
              ]
            }])
          }
        }.each do |title, params|
          it(title) { run_expand(validate: true, **params) }
        end
      end
    end

    context "@container: @list" do
      {
        empty: {
          input: %({"http://example.com/foo": {"@list": []}}),
          output: %([{"http://example.com/foo": [{"@list": []}]}])
        },
        'coerced empty': {
          input: %({
            "@context": {"http://example.com/foo": {"@container": "@list"}},
            "http://example.com/foo": []
          }),
          output: %([{"http://example.com/foo": [{"@list": []}]}])
        },
        'coerced single element': {
          input: %({
            "@context": {"http://example.com/foo": {"@container": "@list"}},
            "http://example.com/foo": [ "foo" ]
          }),
          output: %([{"http://example.com/foo": [{"@list": [{"@value": "foo"}]}]}])
        },
        'coerced multiple elements': {
          input: %({
            "@context": {"http://example.com/foo": {"@container": "@list"}},
            "http://example.com/foo": [ "foo", "bar" ]
          }),
          output: %([{
            "http://example.com/foo": [{"@list": [ {"@value": "foo"}, {"@value": "bar"} ]}]
          }])
        },
        'native values in list': {
          input: %({
            "http://example.com/foo": {"@list": [1, 2]}
          }),
          output: %([{
            "http://example.com/foo": [{"@list": [{"@value": 1}, {"@value": 2}]}]
          }])
        },
        'explicit list with coerced @id values': {
          input: %({
            "@context": {"http://example.com/foo": {"@type": "@id"}},
            "http://example.com/foo": {"@list": ["http://foo", "http://bar"]}
          }),
          output: %([{
            "http://example.com/foo": [{"@list": [{"@id": "http://foo"}, {"@id": "http://bar"}]}]
          }])
        },
        'explicit list with coerced datatype values': {
          input: %({
            "@context": {"http://example.com/foo": {"@type": "http://www.w3.org/2001/XMLSchema#date"}},
            "http://example.com/foo": {"@list": ["2012-04-12"]}
          }),
          output: %([{
            "http://example.com/foo": [{"@list": [{"@value": "2012-04-12", "@type": "http://www.w3.org/2001/XMLSchema#date"}]}]
          }])
        },
        'expand-0004': {
          input: %({
            "@context": {
              "mylist1": {"@id": "http://example.com/mylist1", "@container": "@list"},
              "mylist2": {"@id": "http://example.com/mylist2", "@container": "@list"},
              "myset2": {"@id": "http://example.com/myset2", "@container": "@set"},
              "myset3": {"@id": "http://example.com/myset3", "@container": "@set"}
            },
            "http://example.org/property": { "@list": "one item" }
          }),
          output: %([
            {
              "http://example.org/property": [
                {
                  "@list": [
                    {
                      "@value": "one item"
                    }
                  ]
                }
              ]
            }
          ])
        },
        '@list containing @list': {
          input: %({
            "http://example.com/foo": {"@list": [{"@list": ["baz"]}]}
          }),
          output: %([{
            "http://example.com/foo": [{"@list": [{"@list": [{"@value": "baz"}]}]}]
          }])
        },
        '@list containing empty @list': {
          input: %({
            "http://example.com/foo": {"@list": [{"@list": []}]}
          }),
          output: %([{
            "http://example.com/foo": [{"@list": [{"@list": []}]}]
          }])
        },
        '@list containing @list (with coercion)': {
          input: %({
            "@context": {"foo": {"@id": "http://example.com/foo", "@container": "@list"}},
            "foo": [{"@list": ["baz"]}]
          }),
          output: %([{
            "http://example.com/foo": [{"@list": [{"@list": [{"@value": "baz"}]}]}]
          }])
        },
        '@list containing empty @list (with coercion)': {
          input: %({
            "@context": {"foo": {"@id": "http://example.com/foo", "@container": "@list"}},
            "foo": [{"@list": []}]
          }),
          output: %([{
            "http://example.com/foo": [{"@list": [{"@list": []}]}]
          }])
        },
        'coerced @list containing an array': {
          input: %({
            "@context": {"foo": {"@id": "http://example.com/foo", "@container": "@list"}},
            "foo": [["baz"]]
          }),
          output: %([{
            "http://example.com/foo": [{"@list": [{"@list": [{"@value": "baz"}]}]}]
          }])
        },
        'coerced @list containing an empty array': {
          input: %({
            "@context": {"foo": {"@id": "http://example.com/foo", "@container": "@list"}},
            "foo": [[]]
          }),
          output: %([{
            "http://example.com/foo": [{"@list": [{"@list": []}]}]
          }])
        },
        'coerced @list containing deep arrays': {
          input: %({
            "@context": {"foo": {"@id": "http://example.com/foo", "@container": "@list"}},
            "foo": [[["baz"]]]
          }),
          output: %([{
            "http://example.com/foo": [{"@list": [{"@list": [{"@list": [{"@value": "baz"}]}]}]}]
          }])
        },
        'coerced @list containing deep empty arrays': {
          input: %({
            "@context": {"foo": {"@id": "http://example.com/foo", "@container": "@list"}},
            "foo": [[[]]]
          }),
          output: %([{
            "http://example.com/foo": [{"@list": [{"@list": [{"@list": []}]}]}]
          }])
        },
        'coerced @list containing multiple lists': {
          input: %({
            "@context": {"foo": {"@id": "http://example.com/foo", "@container": "@list"}},
            "foo": [["a"], ["b"]]
          }),
          output: %([{
            "http://example.com/foo": [{"@list": [
              {"@list": [{"@value": "a"}]},
              {"@list": [{"@value": "b"}]}
            ]}]
          }])
        },
        'coerced @list containing mixed list values': {
          input: %({
            "@context": {"foo": {"@id": "http://example.com/foo", "@container": "@list"}},
            "foo": [["a"], "b"]
          }),
          output: %([{
            "http://example.com/foo": [{"@list": [
              {"@list": [{"@value": "a"}]},
              {"@value": "b"}
            ]}]
          }])
        }
      }.each do |title, params|
        it(title) { run_expand params }
      end
    end

    context "@container: @set" do
      {
        empty: {
          input: %({"http://example.com/foo": {"@set": []}}),
          output: %([{"http://example.com/foo": []}])
        },
        'coerced empty': {
          input: %({
            "@context": {"http://example.com/foo": {"@container": "@set"}},
            "http://example.com/foo": []
          }),
          output: %([{
            "http://example.com/foo": []
          }])
        },
        'coerced single element': {
          input: %({
            "@context": {"http://example.com/foo": {"@container": "@set"}},
            "http://example.com/foo": [ "foo" ]
          }),
          output: %([{
            "http://example.com/foo": [ {"@value": "foo"} ]
          }])
        },
        'coerced multiple elements': {
          input: %({
            "@context": {"http://example.com/foo": {"@container": "@set"}},
            "http://example.com/foo": [ "foo", "bar" ]
          }),
          output: %([{
            "http://example.com/foo": [ {"@value": "foo"}, {"@value": "bar"} ]
          }])
        },
        'array containing set': {
          input: %({
            "http://example.com/foo": [{"@set": []}]
          }),
          output: %([{
            "http://example.com/foo": []
          }])
        },
        'Free-floating values in sets': {
          input: %({
            "@context": {"property": "http://example.com/property"},
            "@graph": [{
                "@set": [
                    "free-floating strings in set objects are removed",
                    {"@id": "http://example.com/free-floating-node"},
                    {
                        "@id": "http://example.com/node",
                        "property": "nodes with properties are not removed"
                    }
                ]
            }]
          }),
          output: %([{
            "@id": "http://example.com/node",
            "http://example.com/property": [
              {
                "@value": "nodes with properties are not removed"
              }
            ]
          }])
        }
      }.each do |title, params|
        it(title) { run_expand params }
      end
    end

    context "@container: @language" do
      {
        'simple map': {
          input: %({
            "@context": {
              "vocab": "http://example.com/vocab/",
              "label": {
                "@id": "vocab:label",
                "@container": "@language"
              }
            },
            "@id": "http://example.com/queen",
            "label": {
              "en": "The Queen",
              "de": [ "Die Königin", "Ihre Majestät" ]
            }
          }),
          output: %([
            {
              "@id": "http://example.com/queen",
              "http://example.com/vocab/label": [
                {"@value": "Die Königin", "@language": "de"},
                {"@value": "Ihre Majestät", "@language": "de"},
                {"@value": "The Queen", "@language": "en"}
              ]
            }
          ])
        },
        'simple map with @none': {
          input: %({
            "@context": {
              "vocab": "http://example.com/vocab/",
              "label": {
                "@id": "vocab:label",
                "@container": "@language"
              }
            },
            "@id": "http://example.com/queen",
            "label": {
              "en": "The Queen",
              "de": [ "Die Königin", "Ihre Majestät" ],
              "@none": "The Queen"
            }
          }),
          output: %([
            {
              "@id": "http://example.com/queen",
              "http://example.com/vocab/label": [
                {"@value": "The Queen"},
                {"@value": "Die Königin", "@language": "de"},
                {"@value": "Ihre Majestät", "@language": "de"},
                {"@value": "The Queen", "@language": "en"}
              ]
            }
          ])
        },
        'simple map with alias of @none': {
          input: %({
            "@context": {
              "vocab": "http://example.com/vocab/",
              "label": {
                "@id": "vocab:label",
                "@container": "@language"
              },
              "none": "@none"
            },
            "@id": "http://example.com/queen",
            "label": {
              "en": "The Queen",
              "de": [ "Die Königin", "Ihre Majestät" ],
              "none": "The Queen"
            }
          }),
          output: %([
            {
              "@id": "http://example.com/queen",
              "http://example.com/vocab/label": [
                {"@value": "Die Königin", "@language": "de"},
                {"@value": "Ihre Majestät", "@language": "de"},
                {"@value": "The Queen", "@language": "en"},
                {"@value": "The Queen"}
              ]
            }
          ])
        },
        'simple map with default direction': {
          input: %({
            "@context": {
              "@direction": "ltr",
              "vocab": "http://example.com/vocab/",
              "label": {
                "@id": "vocab:label",
                "@container": "@language"
              }
            },
            "@id": "http://example.com/queen",
            "label": {
              "en": "The Queen",
              "de": [ "Die Königin", "Ihre Majestät" ]
            }
          }),
          output: %([
            {
              "@id": "http://example.com/queen",
              "http://example.com/vocab/label": [
                {"@value": "Die Königin", "@language": "de", "@direction": "ltr"},
                {"@value": "Ihre Majestät", "@language": "de", "@direction": "ltr"},
                {"@value": "The Queen", "@language": "en", "@direction": "ltr"}
              ]
            }
          ])
        },
        'simple map with term direction': {
          input: %({
            "@context": {
              "vocab": "http://example.com/vocab/",
              "label": {
                "@id": "vocab:label",
                "@direction": "ltr",
                "@container": "@language"
              }
            },
            "@id": "http://example.com/queen",
            "label": {
              "en": "The Queen",
              "de": [ "Die Königin", "Ihre Majestät" ]
            }
          }),
          output: %([
            {
              "@id": "http://example.com/queen",
              "http://example.com/vocab/label": [
                {"@value": "Die Königin", "@language": "de", "@direction": "ltr"},
                {"@value": "Ihre Majestät", "@language": "de", "@direction": "ltr"},
                {"@value": "The Queen", "@language": "en", "@direction": "ltr"}
              ]
            }
          ])
        },
        'simple map with overriding term direction': {
          input: %({
            "@context": {
              "vocab": "http://example.com/vocab/",
              "@direction": "rtl",
              "label": {
                "@id": "vocab:label",
                "@direction": "ltr",
                "@container": "@language"
              }
            },
            "@id": "http://example.com/queen",
            "label": {
              "en": "The Queen",
              "de": [ "Die Königin", "Ihre Majestät" ]
            }
          }),
          output: %([
            {
              "@id": "http://example.com/queen",
              "http://example.com/vocab/label": [
                {"@value": "Die Königin", "@language": "de", "@direction": "ltr"},
                {"@value": "Ihre Majestät", "@language": "de", "@direction": "ltr"},
                {"@value": "The Queen", "@language": "en", "@direction": "ltr"}
              ]
            }
          ])
        },
        'simple map with overriding null direction': {
          input: %({
            "@context": {
              "vocab": "http://example.com/vocab/",
              "@direction": "rtl",
              "label": {
                "@id": "vocab:label",
                "@direction": null,
                "@container": "@language"
              }
            },
            "@id": "http://example.com/queen",
            "label": {
              "en": "The Queen",
              "de": [ "Die Königin", "Ihre Majestät" ]
            }
          }),
          output: %([
            {
              "@id": "http://example.com/queen",
              "http://example.com/vocab/label": [
                {"@value": "Die Königin", "@language": "de"},
                {"@value": "Ihre Majestät", "@language": "de"},
                {"@value": "The Queen", "@language": "en"}
              ]
            }
          ])
        },
        'expand-0035': {
          input: %({
            "@context": {
              "@vocab": "http://example.com/vocab/",
              "@language": "it",
              "label": {
                "@container": "@language"
              }
            },
            "@id": "http://example.com/queen",
            "label": {
              "en": "The Queen",
              "de": [ "Die Königin", "Ihre Majestät" ]
            },
            "http://example.com/vocab/label": [
              "Il re",
              { "@value": "The king", "@language": "en" }
            ]
          }),
          output: %([
            {
              "@id": "http://example.com/queen",
              "http://example.com/vocab/label": [
                {"@value": "Il re", "@language": "it"},
                {"@value": "The king", "@language": "en"},
                {"@value": "Die Königin", "@language": "de"},
                {"@value": "Ihre Majestät", "@language": "de"},
                {"@value": "The Queen", "@language": "en"}
              ]
            }
          ])
        }
      }.each do |title, params|
        it(title) { run_expand params }
      end
    end

    context "@container: @id" do
      {
        'Adds @id to object not having an @id': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "idmap": {"@container": "@id"}
            },
            "idmap": {
              "http://example.org/foo": {"label": "Object with @id <foo>"},
              "_:bar": {"label": "Object with @id _:bar"}
            }
          }),
          output: %([{
            "http://example/idmap": [
              {"http://example/label": [{"@value": "Object with @id _:bar"}], "@id": "_:bar"},
              {"http://example/label": [{"@value": "Object with @id <foo>"}], "@id": "http://example.org/foo"}
            ]
          }])
        },
        'Retains @id in object already having an @id': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "idmap": {"@container": "@id"}
            },
            "idmap": {
              "http://example.org/foo": {"@id": "http://example.org/bar", "label": "Object with @id <foo>"},
              "_:bar": {"@id": "_:foo", "label": "Object with @id _:bar"}
            }
          }),
          output: %([{
            "http://example/idmap": [
              {"@id": "_:foo", "http://example/label": [{"@value": "Object with @id _:bar"}]},
              {"@id": "http://example.org/bar", "http://example/label": [{"@value": "Object with @id <foo>"}]}
            ]
          }])
        },
        'Adds expanded @id to object': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "idmap": {"@container": "@id"}
            },
            "idmap": {
              "foo": {"label": "Object with @id <foo>"}
            }
          }),
          output: %([{
            "http://example/idmap": [
              {"http://example/label": [{"@value": "Object with @id <foo>"}], "@id": "http://example.org/foo"}
            ]
          }]),
          base: "http://example.org/"
        },
        'Raises InvalidContainerMapping if processingMode is 1.0': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "idmap": {"@container": "@id"}
            },
            "idmap": {
              "http://example.org/foo": {"label": "Object with @id <foo>"},
              "_:bar": {"label": "Object with @id _:bar"}
            }
          }),
          processingMode: 'json-ld-1.0',
          exception: JSON::LD::JsonLdError::InvalidContainerMapping
        },
        'Does not add @id if it is @none, or expands to @none': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "idmap": {"@container": "@id"},
              "none": "@none"
            },
            "idmap": {
              "@none": {"label": "Object with no @id"},
              "none": {"label": "Another object with no @id"}
            }
          }),
          output: %([{
            "http://example/idmap": [
              {"http://example/label": [{"@value": "Object with no @id"}]},
              {"http://example/label": [{"@value": "Another object with no @id"}]}
            ]
          }])
        }
      }.each do |title, params|
        it(title) { run_expand({ processingMode: "json-ld-1.1" }.merge(params)) }
      end
    end

    context "@container: @type" do
      {
        'Adds @type to object not having an @type': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "typemap": {"@container": "@type"}
            },
            "typemap": {
              "http://example.org/foo": {"label": "Object with @type <foo>"},
              "_:bar": {"label": "Object with @type _:bar"}
            }
          }),
          output: %([{
            "http://example/typemap": [
              {"http://example/label": [{"@value": "Object with @type _:bar"}], "@type": ["_:bar"]},
              {"http://example/label": [{"@value": "Object with @type <foo>"}], "@type": ["http://example.org/foo"]}
            ]
          }])
        },
        'Prepends @type in object already having an @type': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "typemap": {"@container": "@type"}
            },
            "typemap": {
              "http://example.org/foo": {"@type": "http://example.org/bar", "label": "Object with @type <foo>"},
              "_:bar": {"@type": "_:foo", "label": "Object with @type _:bar"}
            }
          }),
          output: %([{
            "http://example/typemap": [
              {
                "@type": ["_:bar", "_:foo"],
                "http://example/label": [{"@value": "Object with @type _:bar"}]
              },
              {
                "@type": ["http://example.org/foo", "http://example.org/bar"],
                "http://example/label": [{"@value": "Object with @type <foo>"}]
              }
            ]
          }])
        },
        'Adds vocabulary expanded @type to object': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "typemap": {"@container": "@type"}
            },
            "typemap": {
              "Foo": {"label": "Object with @type <foo>"}
            }
          }),
          output: %([{
            "http://example/typemap": [
              {"http://example/label": [{"@value": "Object with @type <foo>"}], "@type": ["http://example/Foo"]}
            ]
          }])
        },
        'Adds document expanded @type to object': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "typemap": {"@container": "@type"},
              "label": "http://example/label"
            },
            "typemap": {
              "Foo": {"label": "Object with @type <foo>"}
            }
          }),
          output: %([{
            "http://example/typemap": [
              {"http://example/label": [{"@value": "Object with @type <foo>"}], "@type": ["http://example/Foo"]}
            ]
          }])
        },
        'Does not add @type if it is @none, or expands to @none': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "typemap": {"@container": "@type"},
              "none": "@none"
            },
            "typemap": {
              "@none": {"label": "Object with no @type"},
              "none": {"label": "Another object with no @type"}
            }
          }),
          output: %([{
            "http://example/typemap": [
              {"http://example/label": [{"@value": "Object with no @type"}]},
              {"http://example/label": [{"@value": "Another object with no @type"}]}
            ]
          }])
        },
        'Raises InvalidContainerMapping if processingMode is 1.0': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "typemap": {"@container": "@type"}
            },
            "typemap": {
              "http://example.org/foo": {"label": "Object with @type <foo>"},
              "_:bar": {"label": "Object with @type _:bar"}
            }
          }),
          processingMode: 'json-ld-1.0',
          exception: JSON::LD::JsonLdError::InvalidContainerMapping
        }
      }.each do |title, params|
        it(title) { run_expand({ processingMode: "json-ld-1.1" }.merge(params)) }
      end
    end

    context "@container: @graph" do
      {
        'Creates a graph object given a value': {
          input: %({
            "@context": {
              "@vocab": "http://example.org/",
              "input": {"@container": "@graph"}
            },
            "input": {
              "value": "x"
            }
          }),
          output: %([{
            "http://example.org/input": [{
              "@graph": [{
                "http://example.org/value": [{"@value": "x"}]
              }]
            }]
          }])
        },
        'Creates a graph object within an array given a value': {
          input: %({
            "@context": {
              "@vocab": "http://example.org/",
              "input": {"@container": ["@graph", "@set"]}
            },
            "input": {
              "value": "x"
            }
          }),
          output: %([{
            "http://example.org/input": [{
              "@graph": [{
                "http://example.org/value": [{"@value": "x"}]
              }]
            }]
          }])
        },
        'Creates an graph object if value is a graph': {
          input: %({
            "@context": {
              "@vocab": "http://example.org/",
              "input": {"@container": "@graph"}
            },
            "input": {
              "@graph": {
                "value": "x"
              }
            }
          }),
          output: %([{
            "http://example.org/input": [{
              "@graph": [{
                "@graph": [{
                  "http://example.org/value": [{"@value": "x"}]
                }]
              }]
            }]
          }])
        }
      }.each do |title, params|
        it(title) { run_expand({ processingMode: "json-ld-1.1" }.merge(params)) }
      end

      context "+ @index" do
        {
          'Creates a graph object given an indexed value': {
            input: %({
              "@context": {
                "@vocab": "http://example.org/",
                "input": {"@container": ["@graph", "@index"]}
              },
              "input": {
                "g1": {"value": "x"}
              }
            }),
            output: %([{
              "http://example.org/input": [{
                "@index": "g1",
                "@graph": [{
                  "http://example.org/value": [{"@value": "x"}]
                }]
              }]
            }])
          },
          'Creates a graph object given an indexed value with index @none': {
            input: %({
              "@context": {
                "@vocab": "http://example.org/",
                "input": {"@container": ["@graph", "@index"]}
              },
              "input": {
                "@none": {"value": "x"}
              }
            }),
            output: %([{
              "http://example.org/input": [{
                "@graph": [{
                  "http://example.org/value": [{"@value": "x"}]
                }]
              }]
            }])
          },
          'Creates a graph object given an indexed value with index alias of @none': {
            input: %({
              "@context": {
                "@vocab": "http://example.org/",
                "input": {"@container": ["@graph", "@index"]},
                "none": "@none"
              },
              "input": {
                "none": {"value": "x"}
              }
            }),
            output: %([{
              "http://example.org/input": [{
                "@graph": [{
                  "http://example.org/value": [{"@value": "x"}]
                }]
              }]
            }])
          },
          'Creates a graph object given an indexed value with @set': {
            input: %({
              "@context": {
                "@vocab": "http://example.org/",
                "input": {"@container": ["@graph", "@index", "@set"]}
              },
              "input": {
                "g1": {"value": "x"}
              }
            }),
            output: %([{
              "http://example.org/input": [{
                "@index": "g1",
                "@graph": [{
                  "http://example.org/value": [{"@value": "x"}]
                }]
              }]
            }])
          },
          'Does not create a new graph object if indexed value is already a graph object': {
            input: %({
              "@context": {
                "@vocab": "http://example.org/",
                "input": {"@container": ["@graph", "@index"]}
              },
              "input": {
                "g1": {
                  "@graph": {
                    "value": "x"
                  }
                }
              }
            }),
            output: %([{
              "http://example.org/input": [{
                "@index": "g1",
                "@graph": [{
                  "http://example.org/value": [{"@value": "x"}]
                }]
              }]
            }])
          }
        }.each do |title, params|
          it(title) { run_expand({ processingMode: "json-ld-1.1" }.merge(params)) }
        end

        context "@index: property" do
          {
            'it expands to property value, instead of @index': {
              input: %({
                "@context": {
                  "@version": 1.1,
                  "@vocab": "http://example.org/",
                  "input": {"@container": ["@graph", "@index"], "@index": "prop"}
                },
                "input": {
                  "g1": {"value": "x"}
                }
              }),
              output: %([{
                "http://example.org/input": [{
                  "http://example.org/prop": [{"@value": "g1"}],
                  "@graph": [{
                    "http://example.org/value": [{"@value": "x"}]
                  }]
                }]
              }])
            }
          }.each do |title, params|
            it(title) { run_expand(validate: true, **params) }
          end
        end
      end

      context "+ @id" do
        {
          'Creates a graph object given an indexed value': {
            input: %({
              "@context": {
                "@vocab": "http://example.org/",
                "input": {"@container": ["@graph", "@id"]}
              },
              "input": {
                "http://example.com/g1": {"value": "x"}
              }
            }),
            output: %([{
              "http://example.org/input": [{
                "@id": "http://example.com/g1",
                "@graph": [{
                  "http://example.org/value": [{"@value": "x"}]
                }]
              }]
            }])
          },
          'Creates a graph object given an indexed value of @none': {
            input: %({
              "@context": {
                "@vocab": "http://example.org/",
                "input": {"@container": ["@graph", "@id"]}
              },
              "input": {
                "@none": {"value": "x"}
              }
            }),
            output: %([{
              "http://example.org/input": [{
                "@graph": [{
                  "http://example.org/value": [{"@value": "x"}]
                }]
              }]
            }])
          },
          'Creates a graph object given an indexed value of alias of @none': {
            input: %({
              "@context": {
                "@vocab": "http://example.org/",
                "input": {"@container": ["@graph", "@id"]},
                "none": "@none"
              },
              "input": {
                "none": {"value": "x"}
              }
            }),
            output: %([{
              "http://example.org/input": [{
                "@graph": [{
                  "http://example.org/value": [{"@value": "x"}]
                }]
              }]
            }])
          },
          'Creates a graph object given an indexed value with @set': {
            input: %({
              "@context": {
                "@vocab": "http://example.org/",
                "input": {"@container": ["@graph", "@id", "@set"]}
              },
              "input": {
                "http://example.com/g1": {"value": "x"}
              }
            }),
            output: %([{
              "http://example.org/input": [{
                "@id": "http://example.com/g1",
                "@graph": [{
                  "http://example.org/value": [{"@value": "x"}]
                }]
              }]
            }])
          },
          'Does not create a new graph object if indexed value is already a graph object': {
            input: %({
              "@context": {
                "@vocab": "http://example.org/",
                "input": {"@container": ["@graph", "@id"]}
              },
              "input": {
                "http://example.com/g1": {
                  "@graph": {
                    "value": "x"
                  }
                }
              }
            }),
            output: %([{
              "http://example.org/input": [{
                "@id": "http://example.com/g1",
                "@graph": [{
                  "http://example.org/value": [{"@value": "x"}]
                }]
              }]
            }])
          }
        }.each do |title, params|
          it(title) { run_expand({ processingMode: "json-ld-1.1" }.merge(params)) }
        end
      end
    end

    context "@included" do
      {
        'Basic Included array': {
          input: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/"
            },
            "prop": "value",
            "@included": [{
              "prop": "value2"
            }]
          }),
          output: %([{
            "http://example.org/prop": [{"@value": "value"}],
            "@included": [{
              "http://example.org/prop": [{"@value": "value2"}]
            }]
          }])
        },
        'Basic Included object': {
          input: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/"
            },
            "prop": "value",
            "@included": {
              "prop": "value2"
            }
          }),
          output: %([{
            "http://example.org/prop": [{"@value": "value"}],
            "@included": [{
              "http://example.org/prop": [{"@value": "value2"}]
            }]
          }])
        },
        'Multiple properties mapping to @included are folded together': {
          input: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/",
              "included1": "@included",
              "included2": "@included"
            },
            "included1": {"prop": "value1"},
            "included2": {"prop": "value2"}
          }),
          output: %([{
            "@included": [
              {"http://example.org/prop": [{"@value": "value1"}]},
              {"http://example.org/prop": [{"@value": "value2"}]}
            ]
          }])
        },
        'Included containing @included': {
          input: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/"
            },
            "prop": "value",
            "@included": {
              "prop": "value2",
              "@included": {
                "prop": "value3"
              }
            }
          }),
          output: %([{
            "http://example.org/prop": [{"@value": "value"}],
            "@included": [{
              "http://example.org/prop": [{"@value": "value2"}],
              "@included": [{
                "http://example.org/prop": [{"@value": "value3"}]
              }]
            }]
          }])
        },
        'Property value with @included': {
          input: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/"
            },
            "prop": {
              "@type": "Foo",
              "@included": {
                "@type": "Bar"
              }
            }
          }),
          output: %([{
            "http://example.org/prop": [{
              "@type": ["http://example.org/Foo"],
              "@included": [{
                "@type": ["http://example.org/Bar"]
              }]
            }]
          }])
        },
        'json.api example': {
          input: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/vocab#",
              "@base": "http://example.org/base/",
              "id": "@id",
              "type": "@type",
              "data": "@nest",
              "attributes": "@nest",
              "links": "@nest",
              "relationships": "@nest",
              "included": "@included",
              "self": {"@type": "@id"},
              "related": {"@type": "@id"},
              "comments": {
                "@context": {
                  "data": null
                }
              }
            },
            "data": [{
              "type": "articles",
              "id": "1",
              "attributes": {
                "title": "JSON:API paints my bikeshed!"
              },
              "links": {
                "self": "http://example.com/articles/1"
              },
              "relationships": {
                "author": {
                  "links": {
                    "self": "http://example.com/articles/1/relationships/author",
                    "related": "http://example.com/articles/1/author"
                  },
                  "data": { "type": "people", "id": "9" }
                },
                "comments": {
                  "links": {
                    "self": "http://example.com/articles/1/relationships/comments",
                    "related": "http://example.com/articles/1/comments"
                  },
                  "data": [
                    { "type": "comments", "id": "5" },
                    { "type": "comments", "id": "12" }
                  ]
                }
              }
            }],
            "included": [{
              "type": "people",
              "id": "9",
              "attributes": {
                "first-name": "Dan",
                "last-name": "Gebhardt",
                "twitter": "dgeb"
              },
              "links": {
                "self": "http://example.com/people/9"
              }
            }, {
              "type": "comments",
              "id": "5",
              "attributes": {
                "body": "First!"
              },
              "relationships": {
                "author": {
                  "data": { "type": "people", "id": "2" }
                }
              },
              "links": {
                "self": "http://example.com/comments/5"
              }
            }, {
              "type": "comments",
              "id": "12",
              "attributes": {
                "body": "I like XML better"
              },
              "relationships": {
                "author": {
                  "data": { "type": "people", "id": "9" }
                }
              },
              "links": {
                "self": "http://example.com/comments/12"
              }
            }]
          }),
          output: %([{
            "@id": "http://example.org/base/1",
            "@type": ["http://example.org/vocab#articles"],
            "http://example.org/vocab#title": [{"@value": "JSON:API paints my bikeshed!"}],
            "http://example.org/vocab#self": [{"@id": "http://example.com/articles/1"}],
            "http://example.org/vocab#author": [{
              "@id": "http://example.org/base/9",
              "@type": ["http://example.org/vocab#people"],
              "http://example.org/vocab#self": [{"@id": "http://example.com/articles/1/relationships/author"}],
              "http://example.org/vocab#related": [{"@id": "http://example.com/articles/1/author"}]
            }],
            "http://example.org/vocab#comments": [{
              "http://example.org/vocab#self": [{"@id": "http://example.com/articles/1/relationships/comments"}],
              "http://example.org/vocab#related": [{"@id": "http://example.com/articles/1/comments"}]
            }],
            "@included": [{
              "@id": "http://example.org/base/9",
              "@type": ["http://example.org/vocab#people"],
              "http://example.org/vocab#first-name": [{"@value": "Dan"}],
              "http://example.org/vocab#last-name": [{"@value": "Gebhardt"}],
              "http://example.org/vocab#twitter": [{"@value": "dgeb"}],
              "http://example.org/vocab#self": [{"@id": "http://example.com/people/9"}]
            }, {
              "@id": "http://example.org/base/5",
              "@type": ["http://example.org/vocab#comments"],
              "http://example.org/vocab#body": [{"@value": "First!"}],
              "http://example.org/vocab#author": [{
                "@id": "http://example.org/base/2",
                "@type": ["http://example.org/vocab#people"]
              }],
              "http://example.org/vocab#self": [{"@id": "http://example.com/comments/5"}]
            }, {
              "@id": "http://example.org/base/12",
              "@type": ["http://example.org/vocab#comments"],
              "http://example.org/vocab#body": [{"@value": "I like XML better"}],
              "http://example.org/vocab#author": [{
                "@id": "http://example.org/base/9",
                "@type": ["http://example.org/vocab#people"]
              }],
              "http://example.org/vocab#self": [{"@id": "http://example.com/comments/12"}]
            }]
          }])
        },
        'Error if @included value is a string': {
          input: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/"
            },
            "@included": "string"
          }),
          exception: JSON::LD::JsonLdError::InvalidIncludedValue
        },
        'Error if @included value is a value object': {
          input: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/"
            },
            "@included": {"@value": "value"}
          }),
          exception: JSON::LD::JsonLdError::InvalidIncludedValue
        },
        'Error if @included value is a list object': {
          input: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/"
            },
            "@included": {"@list": ["value"]}
          }),
          exception: JSON::LD::JsonLdError::InvalidIncludedValue
        }
      }.each do |title, params|
        it(title) { run_expand(params) }
      end
    end

    context "@nest" do
      {
        'Expands input using @nest': {
          input: %({
            "@context": {"@vocab": "http://example.org/"},
            "p1": "v1",
            "@nest": {
              "p2": "v2"
            }
          }),
          output: %([{
            "http://example.org/p1": [{"@value": "v1"}],
            "http://example.org/p2": [{"@value": "v2"}]
          }])
        },
        'Expands input using aliased @nest': {
          input: %({
            "@context": {
              "@vocab": "http://example.org/",
              "nest": "@nest"
            },
            "p1": "v1",
            "nest": {
              "p2": "v2"
            }
          }),
          output: %([{
            "http://example.org/p1": [{"@value": "v1"}],
            "http://example.org/p2": [{"@value": "v2"}]
          }])
        },
        'Appends nested values when property at base and nested': {
          input: %({
            "@context": {
              "@vocab": "http://example.org/",
              "nest": "@nest"
            },
            "p1": "v1",
            "nest": {
              "p2": "v3"
            },
            "p2": "v2"
          }),
          output: %([{
            "http://example.org/p1": [{"@value": "v1"}],
            "http://example.org/p2": [
              {"@value": "v2"},
              {"@value": "v3"}
            ]
          }])
        },
        'Appends nested values from all @nest aliases in term order': {
          input: %({
            "@context": {
              "@vocab": "http://example.org/",
              "nest1": "@nest",
              "nest2": "@nest"
            },
            "p1": "v1",
            "nest2": {
              "p2": "v4"
            },
            "p2": "v2",
            "nest1": {
              "p2": "v3"
            }
          }),
          output: %([{
            "http://example.org/p1": [{"@value": "v1"}],
            "http://example.org/p2": [
              {"@value": "v2"},
              {"@value": "v3"},
              {"@value": "v4"}
            ]
          }])
        },
        'Nested nested containers': {
          input: %({
            "@context": {
              "@vocab": "http://example.org/"
            },
            "p1": "v1",
            "@nest": {
              "p2": "v3",
              "@nest": {
                "p2": "v4"
              }
            },
            "p2": "v2"
          }),
          output: %([{
            "http://example.org/p1": [{"@value": "v1"}],
            "http://example.org/p2": [
              {"@value": "v2"},
              {"@value": "v3"},
              {"@value": "v4"}
            ]
          }])
        },
        'Arrays of nested values': {
          input: %({
            "@context": {
              "@vocab": "http://example.org/",
              "nest": "@nest"
            },
            "p1": "v1",
            "nest": {
              "p2": ["v4", "v5"]
            },
            "p2": ["v2", "v3"]
          }),
          output: %([{
            "http://example.org/p1": [{"@value": "v1"}],
            "http://example.org/p2": [
              {"@value": "v2"},
              {"@value": "v3"},
              {"@value": "v4"},
              {"@value": "v5"}
            ]
          }])
        },
        'A nest of arrays': {
          input: %({
            "@context": {
              "@vocab": "http://example.org/",
              "nest": "@nest"
            },
            "p1": "v1",
            "nest": [{
              "p2": "v4"
            }, {
              "p2": "v5"
            }],
            "p2": ["v2", "v3"]
          }),
          output: %([{
            "http://example.org/p1": [{"@value": "v1"}],
            "http://example.org/p2": [
              {"@value": "v2"},
              {"@value": "v3"},
              {"@value": "v4"},
              {"@value": "v5"}
            ]
          }])
        },
        '@nest MUST NOT have a string value': {
          input: %({
            "@context": {"@vocab": "http://example.org/"},
            "@nest": "This should generate an error"
          }),
          exception: JSON::LD::JsonLdError::InvalidNestValue
        },
        '@nest MUST NOT have a boolen value': {
          input: %({
            "@context": {"@vocab": "http://example.org/"},
            "@nest": true
          }),
          exception: JSON::LD::JsonLdError::InvalidNestValue
        },
        '@nest MUST NOT have a numeric value': {
          input: %({
            "@context": {"@vocab": "http://example.org/"},
            "@nest": 1
          }),
          exception: JSON::LD::JsonLdError::InvalidNestValue
        },
        '@nest MUST NOT have a value object value': {
          input: %({
            "@context": {"@vocab": "http://example.org/"},
            "@nest": {"@value": "This should generate an error"}
          }),
          exception: JSON::LD::JsonLdError::InvalidNestValue
        },
        '@nest in term definition MUST NOT be a non-@nest keyword': {
          input: %({
            "@context": {
              "@vocab": "http://example.org/",
              "nest": {"@nest": "@id"}
            },
            "nest": "This should generate an error"
          }),
          exception: JSON::LD::JsonLdError::InvalidNestValue
        },
        '@nest in term definition MUST NOT have a boolen value': {
          input: %({
            "@context": {
              "@vocab": "http://example.org/",
              "nest": {"@nest": true}
            },
            "nest": "This should generate an error"
          }),
          exception: JSON::LD::JsonLdError::InvalidNestValue
        },
        '@nest in term definition MUST NOT have a numeric value': {
          input: %({
            "@context": {
              "@vocab": "http://example.org/",
              "nest": {"@nest": 123}
            },
            "nest": "This should generate an error"
          }),
          exception: JSON::LD::JsonLdError::InvalidNestValue
        },
        'Nested @container: @list': {
          input: %({
            "@context": {
              "@vocab": "http://example.org/",
              "list": {"@container": "@list", "@nest": "nestedlist"},
              "nestedlist": "@nest"
            },
            "nestedlist": {
              "list": ["a", "b"]
            }
          }),
          output: %([{
            "http://example.org/list": [{"@list": [
              {"@value": "a"},
              {"@value": "b"}
            ]}]
          }])
        },
        'Nested @container: @index': {
          input: %({
            "@context": {
              "@vocab": "http://example.org/",
              "index": {"@container": "@index", "@nest": "nestedindex"},
              "nestedindex": "@nest"
            },
            "nestedindex": {
              "index": {
                "A": "a",
                "B": "b"
              }
            }
          }),
          output: %([{
            "http://example.org/index": [
              {"@value": "a", "@index": "A"},
              {"@value": "b", "@index": "B"}
            ]
          }])
        },
        'Nested @container: @language': {
          input: %({
            "@context": {
              "@vocab": "http://example.org/",
              "container": {"@container": "@language", "@nest": "nestedlanguage"},
              "nestedlanguage": "@nest"
            },
            "nestedlanguage": {
              "container": {
                "en": "The Queen",
                "de": "Die Königin"
              }
            }
          }),
          output: %([{
            "http://example.org/container": [
              {"@value": "Die Königin", "@language": "de"},
              {"@value": "The Queen", "@language": "en"}
            ]
          }])
        },
        'Nested @container: @type': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "typemap": {"@container": "@type", "@nest": "nestedtypemap"},
              "nestedtypemap": "@nest"
            },
            "nestedtypemap": {
              "typemap": {
                "http://example.org/foo": {"label": "Object with @type <foo>"},
                "_:bar": {"label": "Object with @type _:bar"}
              }
            }
          }),
          output: %([{
            "http://example/typemap": [
              {"http://example/label": [{"@value": "Object with @type _:bar"}], "@type": ["_:bar"]},
              {"http://example/label": [{"@value": "Object with @type <foo>"}], "@type": ["http://example.org/foo"]}
            ]
          }])
        },
        'Nested @container: @id': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "idmap": {"@container": "@id", "@nest": "nestedidmap"},
              "nestedidmap": "@nest"
            },
            "nestedidmap": {
              "idmap": {
                "http://example.org/foo": {"label": "Object with @id <foo>"},
                "_:bar": {"label": "Object with @id _:bar"}
              }
            }
          }),
          output: %([{
            "http://example/idmap": [
              {"http://example/label": [{"@value": "Object with @id _:bar"}], "@id": "_:bar"},
              {"http://example/label": [{"@value": "Object with @id <foo>"}], "@id": "http://example.org/foo"}
            ]
          }])
        },
        'Nest term an invalid keyword': {
          input: %({
            "@context": {
              "term": {"@id": "http://example/term", "@nest": "@id"}
            }
          }),
          exception: JSON::LD::JsonLdError::InvalidNestValue
        },
        'Nest in @reverse': {
          input: %({
            "@context": {
              "term": {"@reverse": "http://example/term", "@nest": "@nest"}
            }
          }),
          exception: JSON::LD::JsonLdError::InvalidReverseProperty
        },
        'Raises InvalidTermDefinition if processingMode is 1.0': {
          input: %({
            "@context": {
              "@vocab": "http://example.org/",
              "list": {"@container": "@list", "@nest": "nestedlist"},
              "nestedlist": "@nest"
            },
            "nestedlist": {
              "list": ["a", "b"]
            }
          }),
          processingMode: 'json-ld-1.0',
          validate: true,
          exception: JSON::LD::JsonLdError::InvalidTermDefinition
        },
        'Applies property scoped contexts which are aliases of @nest': {
          input: %({
            "@context": {
              "@version": 1.1,
              "@vocab": "http://example.org/",
              "nest": {
                "@id": "@nest",
                "@context": {
                  "@vocab": "http://example.org/nest/"
                }
              }
            },
            "nest": {
              "property": "should be in /nest"
            }
          }),
          output: %([{
            "http://example.org/nest/property": [{"@value": "should be in /nest"}]
          }])
        }
      }.each do |title, params|
        it(title) { run_expand({ processingMode: "json-ld-1.1" }.merge(params)) }
      end
    end

    context "scoped context" do
      {
        'adding new term': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "foo": {"@context": {"bar": "http://example.org/bar"}}
            },
            "foo": {
              "bar": "baz"
            }
          }),
          output: %([
            {
              "http://example/foo": [{"http://example.org/bar": [{"@value": "baz"}]}]
            }
          ])
        },
        'overriding a term': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "foo": {"@context": {"bar": {"@type": "@id"}}},
              "bar": {"@type": "http://www.w3.org/2001/XMLSchema#string"}
            },
            "foo": {
              "bar": "http://example/baz"
            }
          }),
          output: %([
            {
              "http://example/foo": [{"http://example/bar": [{"@id": "http://example/baz"}]}]
            }
          ])
        },
        'property and value with different terms mapping to the same expanded property': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "foo": {"@context": {"Bar": {"@id": "bar"}}}
            },
            "foo": {
              "Bar": "baz"
            }
          }),
          output: %([
            {
              "http://example/foo": [{
                "http://example/bar": [
                  {"@value": "baz"}
                ]}
              ]
            }
          ])
        },
        'deep @context affects nested nodes': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "foo": {"@context": {"baz": {"@type": "@vocab"}}}
            },
            "foo": {
              "bar": {
                "baz": "buzz"
              }
            }
          }),
          output: %([
            {
              "http://example/foo": [{
                "http://example/bar": [{
                  "http://example/baz": [{"@id": "http://example/buzz"}]
                }]
              }]
            }
          ])
        },
        'scoped context layers on intemediate contexts': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "b": {"@context": {"c": "http://example.org/c"}}
            },
            "a": {
              "@context": {"@vocab": "http://example.com/"},
              "b": {
                "a": "A in example.com",
                "c": "C in example.org"
              },
              "c": "C in example.com"
            },
            "c": "C in example"
          }),
          output: %([{
            "http://example/a": [{
              "http://example.com/c": [{"@value": "C in example.com"}],
              "http://example/b": [{
                "http://example.com/a": [{"@value": "A in example.com"}],
                "http://example.org/c": [{"@value": "C in example.org"}]
              }]
            }],
            "http://example/c": [{"@value": "C in example"}]
          }])
        },
        'Raises InvalidTermDefinition if processingMode is 1.0': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "foo": {"@context": {"bar": "http://example.org/bar"}}
            },
            "foo": {
              "bar": "baz"
            }
          }),
          processingMode: 'json-ld-1.0',
          validate: true,
          exception: JSON::LD::JsonLdError::InvalidTermDefinition
        },
        'Scoped on id map': {
          input: %({
            "@context": {
              "@version": 1.1,
              "schema": "http://schema.org/",
              "name": "schema:name",
              "body": "schema:articleBody",
              "words": "schema:wordCount",
              "post": {
                "@id": "schema:blogPost",
                "@container": "@id",
                "@context": {
                  "@base": "http://example.com/posts/"
                }
              }
            },
            "@id": "http://example.com/",
            "@type": "schema:Blog",
            "name": "World Financial News",
            "post": {
              "1/en": {
                "body": "World commodities were up today with heavy trading of crude oil...",
                "words": 1539
              },
              "1/de": {
                "body": "Die Werte an Warenbörsen stiegen im Sog eines starken Handels von Rohöl...",
                "words": 1204
              }
            }
          }),
          output: %([{
            "@id": "http://example.com/",
            "@type": ["http://schema.org/Blog"],
            "http://schema.org/name": [{"@value": "World Financial News"}],
            "http://schema.org/blogPost": [{
              "@id": "http://example.com/posts/1/en",
              "http://schema.org/articleBody": [
                {"@value": "World commodities were up today with heavy trading of crude oil..."}
              ],
              "http://schema.org/wordCount": [{"@value": 1539}]
            }, {
              "@id": "http://example.com/posts/1/de",
              "http://schema.org/articleBody": [
                {"@value": "Die Werte an Warenbörsen stiegen im Sog eines starken Handels von Rohöl..."}
              ],
              "http://schema.org/wordCount": [{"@value": 1204}]
            }]
          }])
        }
      }.each do |title, params|
        it(title) { run_expand({ processingMode: "json-ld-1.1" }.merge(params)) }
      end
    end

    context "scoped context on @type" do
      {
        'adding new term': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "Foo": {"@context": {"bar": "http://example.org/bar"}}
            },
            "a": {"@type": "Foo", "bar": "baz"}
          }),
          output: %([
            {
              "http://example/a": [{
                "@type": ["http://example/Foo"],
                "http://example.org/bar": [{"@value": "baz"}]
              }]
            }
          ])
        },
        'overriding a term': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "Foo": {"@context": {"bar": {"@type": "@id"}}},
              "bar": {"@type": "http://www.w3.org/2001/XMLSchema#string"}
            },
            "a": {"@type": "Foo", "bar": "http://example/baz"}
          }),
          output: %([
            {
              "http://example/a": [{
                "@type": ["http://example/Foo"],
                "http://example/bar": [{"@id": "http://example/baz"}]
              }]
            }
          ])
        },
        'alias of @type': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "type": "@type",
              "Foo": {"@context": {"bar": "http://example.org/bar"}}
            },
            "a": {"type": "Foo", "bar": "baz"}
          }),
          output: %([
            {
              "http://example/a": [{
                "@type": ["http://example/Foo"],
                "http://example.org/bar": [{"@value": "baz"}]
              }]
            }
          ])
        },
        'deep @context does not affect nested nodes': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "Foo": {"@context": {"baz": {"@type": "@vocab"}}}
            },
            "@type": "Foo",
            "bar": {"baz": "buzz"}
          }),
          output: %([
            {
              "@type": ["http://example/Foo"],
              "http://example/bar": [{
                "http://example/baz": [{"@value": "buzz"}]
              }]
            }
          ])
        },
        'scoped context layers on intemediate contexts': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "B": {"@context": {"c": "http://example.org/c"}}
            },
            "a": {
              "@context": {"@vocab": "http://example.com/"},
              "@type": "B",
              "a": "A in example.com",
              "c": "C in example.org"
            },
            "c": "C in example"
          }),
          output: %([{
            "http://example/a": [{
              "@type": ["http://example/B"],
              "http://example.com/a": [{"@value": "A in example.com"}],
              "http://example.org/c": [{"@value": "C in example.org"}]
            }],
            "http://example/c": [{"@value": "C in example"}]
          }])
        },
        'with @container: @type': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "typemap": {"@container": "@type"},
              "Type": {"@context": {"a": "http://example.org/a"}}
            },
            "typemap": {
              "Type": {"a": "Object with @type <Type>"}
            }
          }),
          output: %([{
            "http://example/typemap": [
              {"http://example.org/a": [{"@value": "Object with @type <Type>"}], "@type": ["http://example/Type"]}
            ]
          }])
        },
        'orders lexicographically': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "t1": {"@context": {"foo": {"@id": "http://example.com/foo"}}},
              "t2": {"@context": {"foo": {"@id": "http://example.org/foo", "@type": "@id"}}}
            },
            "@type": ["t2", "t1"],
            "foo": "urn:bar"
          }),
          output: %([{
            "@type": ["http://example/t2", "http://example/t1"],
            "http://example.org/foo": [
              {"@id": "urn:bar"}
            ]
          }])
        },
        'Raises InvalidTermDefinition if processingMode is 1.0': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "Foo": {"@context": {"bar": "http://example.org/bar"}}
            },
            "a": {"@type": "Foo", "bar": "baz"}
          }),
          processingMode: 'json-ld-1.0',
          validate: true,
          exception: JSON::LD::JsonLdError::InvalidTermDefinition
        }
      }.each do |title, params|
        it(title) { run_expand({ processingMode: "json-ld-1.1" }.merge(params)) }
      end
    end

    context "@reverse" do
      {
        '@container: @reverse': {
          input: %({
            "@context": {
              "@vocab": "http://example/",
              "rev": { "@reverse": "forward", "@type": "@id"}
            },
            "@id": "http://example/one",
            "rev": "http://example/two"
          }),
          output: %([{
            "@id": "http://example/one",
            "@reverse": {
              "http://example/forward": [
                {
                  "@id": "http://example/two"
                }
              ]
            }
          }])
        },
        'expand-0037': {
          input: %({
            "@context": {
              "name": "http://xmlns.com/foaf/0.1/name"
            },
            "@id": "http://example.com/people/markus",
            "name": "Markus Lanthaler",
            "@reverse": {
              "http://xmlns.com/foaf/0.1/knows": {
                "@id": "http://example.com/people/dave",
                "name": "Dave Longley"
              }
            }
          }),
          output: %([
            {
              "@id": "http://example.com/people/markus",
              "@reverse": {
                "http://xmlns.com/foaf/0.1/knows": [
                  {
                    "@id": "http://example.com/people/dave",
                    "http://xmlns.com/foaf/0.1/name": [
                      {
                        "@value": "Dave Longley"
                      }
                    ]
                  }
                ]
              },
              "http://xmlns.com/foaf/0.1/name": [
                {
                  "@value": "Markus Lanthaler"
                }
              ]
            }
          ])
        },
        'expand-0043': {
          input: %({
            "@context": {
              "name": "http://xmlns.com/foaf/0.1/name",
              "isKnownBy": { "@reverse": "http://xmlns.com/foaf/0.1/knows" }
            },
            "@id": "http://example.com/people/markus",
            "name": "Markus Lanthaler",
            "@reverse": {
              "isKnownBy": [
                {
                  "@id": "http://example.com/people/dave",
                  "name": "Dave Longley"
                },
                {
                  "@id": "http://example.com/people/gregg",
                  "name": "Gregg Kellogg"
                }
              ]
            }
          }),
          output: %([
            {
              "@id": "http://example.com/people/markus",
              "http://xmlns.com/foaf/0.1/knows": [
                {
                  "@id": "http://example.com/people/dave",
                  "http://xmlns.com/foaf/0.1/name": [
                    {
                      "@value": "Dave Longley"
                    }
                  ]
                },
                {
                  "@id": "http://example.com/people/gregg",
                  "http://xmlns.com/foaf/0.1/name": [
                    {
                      "@value": "Gregg Kellogg"
                    }
                  ]
                }
              ],
              "http://xmlns.com/foaf/0.1/name": [
                {
                  "@value": "Markus Lanthaler"
                }
              ]
            }
          ])
        },
        '@reverse object with an @id property': {
          input: %({
            "@id": "http://example/foo",
            "@reverse": {
              "@id": "http://example/bar"
            }
          }),
          exception: JSON::LD::JsonLdError::InvalidReversePropertyMap
        },
        'Explicit and implicit @reverse in same object': {
          input: %({
            "@context": {
              "fooOf": {"@reverse": "ex:foo", "@type": "@id"}
            },
            "@id": "ex:s",
            "fooOf": "ex:o1",
            "@reverse": {
              "ex:bar": {"@id": "ex:o2"}
            }
          }),
          output: %([{
            "@id": "ex:s",
            "@reverse": {
              "ex:bar": [{"@id": "ex:o2"}],
              "ex:foo": [{"@id": "ex:o1"}]
            }
          }])
        },
        'Two properties both with @reverse': {
          input: %({
            "@context": {
              "fooOf": {"@reverse": "ex:foo", "@type": "@id"},
              "barOf": {"@reverse": "ex:bar", "@type": "@id"}
            },
            "@id": "ex:s",
            "fooOf": "ex:o1",
            "barOf": "ex:o2"
          }),
          output: %([{
            "@id": "ex:s",
            "@reverse": {
              "ex:bar": [{"@id": "ex:o2"}],
              "ex:foo": [{"@id": "ex:o1"}]
            }
          }])
        }
      }.each do |title, params|
        it(title) { run_expand params }
      end
    end

    context "JSON-LD-star" do
      {
        'node with embedded subject without rdfstar option': {
          input: %({
            "@id": {
              "@id": "ex:rei",
              "ex:prop": "value"
            },
            "ex:prop": "value2"
          }),
          exception: JSON::LD::JsonLdError::InvalidIdValue
        },
        'node object with @annotation property is ignored without rdfstar option': {
          input: %({
            "@id": "ex:bob",
            "ex:knows": {
              "@id": "ex:fred",
              "@annotation": {
                "ex:certainty": 0.8
              }
            }
          }),
          output: %([{
            "@id": "ex:bob",
            "ex:knows": [{"@id": "ex:fred"}]
          }])
        },
        'value object with @annotation property is ignored without rdfstar option': {
          input: %({
            "@id": "ex:bob",
            "ex:age": {
              "@value": 23,
              "@annotation": {
                "ex:certainty": 0.8
              }
            }
          }),
          output: %([{
            "@id": "ex:bob",
            "ex:age": [{"@value": 23}]
          }])
        }
      }.each do |title, params|
        it(title) { run_expand params }
      end

      {
        'node with embedded subject having no @id': {
          input: %({
            "@id": {
              "ex:prop": "value"
            },
            "ex:prop": "value2"
          }),
          output: %([{
            "@id": {
              "ex:prop": [{"@value": "value"}]
            },
            "ex:prop": [{"@value": "value2"}]
          }])
        },
        'node with embedded subject having IRI @id': {
          input: %({
            "@id": {
              "@id": "ex:rei",
              "ex:prop": "value"
            },
            "ex:prop": "value2"
          }),
          output: %([{
            "@id": {
              "@id": "ex:rei",
              "ex:prop": [{"@value": "value"}]
            },
            "ex:prop": [{"@value": "value2"}]
          }])
        },
        'node with embedded subject having BNode @id': {
          input: %({
            "@id": {
              "@id": "_:rei",
              "ex:prop": "value"
            },
            "ex:prop": "value2"
          }),
          output: %([{
            "@id": {
              "@id": "_:rei",
              "ex:prop": [{"@value": "value"}]
            },
            "ex:prop": [{"@value": "value2"}]
          }])
        },
        'node with embedded subject having a type': {
          input: %({
            "@id": {
              "@id": "ex:rei",
              "@type": "ex:Type"
            },
            "ex:prop": "value2"
          }),
          output: %([{
            "@id": {
              "@id": "ex:rei",
              "@type": ["ex:Type"]
            },
            "ex:prop": [{"@value": "value2"}]
          }])
        },
        'node with embedded subject having an IRI value': {
          input: %({
            "@id": {
              "@id": "ex:rei",
              "ex:prop": {"@id": "ex:value"}
            },
            "ex:prop": "value2"
          }),
          output: %([{
            "@id": {
              "@id": "ex:rei",
              "ex:prop": [{"@id": "ex:value"}]
            },
            "ex:prop": [{"@value": "value2"}]
          }])
        },
        'node with embedded subject having an BNode value': {
          input: %({
            "@id": {
              "@id": "ex:rei",
              "ex:prop": {"@id": "_:value"}
            },
            "ex:prop": "value2"
          }),
          output: %([{
            "@id": {
              "@id": "ex:rei",
              "ex:prop": [{"@id": "_:value"}]
            },
            "ex:prop": [{"@value": "value2"}]
          }])
        },
        'node with recursive embedded subject': {
          input: %({
            "@id": {
              "@id": {
                "@id": "ex:rei",
                "ex:prop": "value3"
              },
              "ex:prop": "value"
            },
            "ex:prop": "value2"
          }),
          output: %([{
            "@id": {
              "@id": {
                "@id": "ex:rei",
                "ex:prop": [{"@value": "value3"}]
              },
              "ex:prop": [{"@value": "value"}]
            },
            "ex:prop": [{"@value": "value2"}]
          }])
        },
        'illegal node with subject having no property': {
          input: %({
            "@id": {
              "@id": "ex:rei"
            },
            "ex:prop": "value3"
          }),
          exception: JSON::LD::JsonLdError::InvalidEmbeddedNode
        },
        'illegal node with subject having multiple properties': {
          input: %({
            "@id": {
              "@id": "ex:rei",
              "ex:prop": ["value1", "value2"]
            },
            "ex:prop": "value3"
          }),
          exception: JSON::LD::JsonLdError::InvalidEmbeddedNode
        },
        'illegal node with subject having multiple types': {
          input: %({
            "@id": {
              "@id": "ex:rei",
              "@type": ["ex:Type1", "ex:Type2"]
            },
            "ex:prop": "value3"
          }),
          exception: JSON::LD::JsonLdError::InvalidEmbeddedNode
        },
        'illegal node with subject having type and property': {
          input: %({
            "@id": {
              "@id": "ex:rei",
              "@type": "ex:Type",
              "ex:prop": "value"
            },
            "ex:prop": "value2"
          }),
          exception: JSON::LD::JsonLdError::InvalidEmbeddedNode
        },
        'node with embedded object': {
          input: %({
            "@id": "ex:subj",
            "ex:value": {
              "@id": {
                "@id": "ex:rei",
                "ex:prop": "value"
              }
            }
          }),
          output: %([{
            "@id": "ex:subj",
            "ex:value": [{
              "@id": {
                "@id": "ex:rei",
                "ex:prop": [{"@value": "value"}]
              }
            }]
          }])
        },
        'node with embedded object having properties': {
          input: %({
            "@id": "ex:subj",
            "ex:value": {
              "@id": {
                "@id": "ex:rei",
                "ex:prop": "value"
              },
              "ex:prop": "value2"
            }
          }),
          output: %([{
            "@id": "ex:subj",
            "ex:value": [{
              "@id": {
                "@id": "ex:rei",
                "ex:prop": [{"@value": "value"}]
              },
              "ex:prop": [{"@value": "value2"}]
            }]
          }])
        },
        'node with recursive embedded object': {
          input: %({
            "@id": "ex:subj",
            "ex:value": {
              "@id": {
                "@id": {
                  "@id": "ex:rei",
                  "ex:prop": "value3"
                },
                "ex:prop": "value"
              },
              "ex:prop": "value2"
            }
          }),
          output: %([{
            "@id": "ex:subj",
            "ex:value": [{
              "@id": {
                "@id": {
                  "@id": "ex:rei",
                  "ex:prop": [{"@value": "value3"}]
                },
                "ex:prop":[{"@value": "value"}]
              },
              "ex:prop": [{"@value": "value2"}]
            }]
          }])
        },
        'node with @annotation property on value object': {
          input: %({
            "@id": "ex:bob",
            "ex:age": {
              "@value": 23,
              "@annotation": {"ex:certainty": 0.8}
            }
          }),
          output: %([{
            "@id": "ex:bob",
            "ex:age": [{
              "@value": 23,
              "@annotation": [{"ex:certainty": [{"@value": 0.8}]}]
            }]
          }])
        },
        'node with @annotation property on node object': {
          input: %({
            "@id": "ex:bob",
            "ex:name": "Bob",
            "ex:knows": {
              "@id": "ex:fred",
              "ex:name": "Fred",
              "@annotation": {"ex:certainty": 0.8}
            }
          }),
          output: %([{
            "@id": "ex:bob",
            "ex:name": [{"@value": "Bob"}],
            "ex:knows": [{
              "@id": "ex:fred",
              "ex:name": [{"@value": "Fred"}],
              "@annotation": [{"ex:certainty": [{"@value": 0.8}]}]
            }]
          }])
        },
        'node with @annotation property multiple values': {
          input: %({
            "@id": "ex:bob",
            "ex:name": "Bob",
            "ex:knows": {
              "@id": "ex:fred",
              "ex:name": "Fred",
              "@annotation": [{
                "ex:certainty": 0.8
              }, {
                "ex:source": {"@id": "http://example.org/"}
              }]
            }
          }),
          output: %([{
            "@id": "ex:bob",
            "ex:name": [{"@value": "Bob"}],
            "ex:knows": [{
              "@id": "ex:fred",
              "ex:name": [{"@value": "Fred"}],
              "@annotation": [{
                "ex:certainty": [{"@value": 0.8}]
              }, {
                "ex:source": [{"@id": "http://example.org/"}]
              }]
            }]
          }])
        },
        'node with @annotation property that is on the top-level is invalid': {
          input: %({
            "@id": "ex:bob",
            "ex:name": "Bob",
            "@annotation": {"ex:prop": "value2"}
          }),
          exception: JSON::LD::JsonLdError::InvalidAnnotation
        },
        'node with @annotation property on a top-level graph node is invalid': {
          input: %({
            "@id": "ex:bob",
            "ex:name": "Bob",
            "@graph": {
              "@id": "ex:fred",
              "ex:name": "Fred",
              "@annotation": {"ex:prop": "value2"}
            }
          }),
          exception: JSON::LD::JsonLdError::InvalidAnnotation
        },
        'node with @annotation property having @id is invalid': {
          input: %({
            "@id": "ex:bob",
            "ex:knows": {
              "@id": "ex:fred",
              "@annotation": {
                "@id": "ex:invalid-ann-id",
                "ex:prop": "value2"
              }
            }
          }),
          exception: JSON::LD::JsonLdError::InvalidAnnotation
        },
        'node with @annotation property with value object value is invalid': {
          input: %({
            "@id": "ex:bob",
            "ex:knows": {
              "@id": "fred",
              "@annotation": "value2"
            }
          }),
          exception: JSON::LD::JsonLdError::InvalidAnnotation
        },
        'node with @annotation on a list': {
          input: %({
            "@id": "ex:bob",
            "ex:knows": {
              "@list": [{"@id": "ex:fred"}],
              "@annotation": {"ex:prop": "value2"}
            }
          }),
          exception: JSON::LD::JsonLdError::InvalidSetOrListObject
        },
        'node with @annotation on a list value': {
          input: %({
            "@id": "ex:bob",
            "ex:knows": {
              "@list": [
                {
                  "@id": "ex:fred",
                  "@annotation": {"ex:prop": "value2"}
                }
              ]
            }
          }),
          exception: JSON::LD::JsonLdError::InvalidAnnotation
        },
        'node with @annotation property on a top-level @included node is invalid': {
          input: %({
            "@id": "ex:bob",
            "ex:name": "Bob",
            "@included": [{
              "@id": "ex:fred",
              "ex:name": "Fred",
              "@annotation": {"ex:prop": "value2"}
            }]
          }),
          exception: JSON::LD::JsonLdError::InvalidAnnotation
        },
        'node with @annotation property on embedded subject': {
          input: %({
            "@id": {
              "@id": "ex:rei",
              "ex:prop": {"@id": "_:value"}
            },
            "ex:prop": {
              "@value": "value2",
              "@annotation": {"ex:certainty": 0.8}
            }
          }),
          output: %([{
            "@id": {
              "@id": "ex:rei",
              "ex:prop": [{"@id": "_:value"}]
            },
            "ex:prop": [{
              "@value": "value2",
              "@annotation": [{
                "ex:certainty": [{"@value": 0.8}]
              }]
            }]
          }])
        },
        'node with @annotation property on embedded object': {
          input: %({
            "@id": "ex:subj",
            "ex:value": {
              "@id": {
                "@id": "ex:rei",
                "ex:prop": "value"
              },
              "@annotation": {"ex:certainty": 0.8}
            }
          }),
          output: %([{
            "@id": "ex:subj",
            "ex:value": [{
              "@id": {
                "@id": "ex:rei",
                "ex:prop": [{"@value": "value"}]
              },
              "@annotation": [{
                "ex:certainty": [{"@value": 0.8}]
              }]
            }]
          }])
        },
        'embedded node with reverse relationship': {
          input: %({
            "@context": {
              "rel": {"@reverse": "ex:rel"}
            },
            "@id": {
              "@id": "ex:rei",
              "rel": {"@id": "ex:value"}
            },
            "ex:prop": "value2"
          }),
          exception: JSON::LD::JsonLdError::InvalidEmbeddedNode
        },
        'embedded node with expanded reverse relationship': {
          input: %({
            "@id": {
              "@id": "ex:rei",
              "@reverse": {
                "ex:rel": {"@id": "ex:value"}
              }
            },
            "ex:prop": "value2"
          }),
          exception: JSON::LD::JsonLdError::InvalidEmbeddedNode
        },
        'embedded node used as subject in reverse relationship': {
          input: %({
            "@context": {
              "rel": {"@reverse": "ex:rel"}
            },
            "@id": {
              "@id": "ex:rei",
              "ex:prop": {"@id": "ex:value"}
            },
            "rel": {"@id": "ex:value2"}
          }),
          output: %([{
            "@id": {
              "@id": "ex:rei",
              "ex:prop": [{"@id": "ex:value"}]
            },
            "@reverse": {
              "ex:rel": [{"@id": "ex:value2"}]
            }
          }])
        },
        'embedded node used as object in reverse relationship': {
          input: %({
            "@context": {
              "rel": {"@reverse": "ex:rel"}
            },
            "@id": "ex:subj",
            "rel": {
              "@id": {
                "@id": "ex:rei",
                "ex:prop": {"@id": "ex:value"}
              },
              "ex:prop": {"@id": "ex:value2"}
            }
          }),
          output: %([{
            "@id": "ex:subj",
            "@reverse": {
              "ex:rel": [{
                "@id": {
                  "@id": "ex:rei",
                  "ex:prop": [{"@id": "ex:value"}]
                },
                "ex:prop": [{"@id": "ex:value2"}]
              }]
            }
          }])
        },
        'node with @annotation property on node object with reverse relationship': {
          input: %({
            "@context": {
              "knownBy": {"@reverse": "ex:knows"}
            },
            "@id": "ex:bob",
            "ex:name": "Bob",
            "knownBy": {
              "@id": "ex:fred",
              "ex:name": "Fred",
              "@annotation": {"ex:certainty": 0.8}
            }
          }),
          output: %([{
            "@id": "ex:bob",
            "ex:name": [{"@value": "Bob"}],
            "@reverse": {
              "ex:knows": [{
                "@id": "ex:fred",
                "ex:name": [{"@value": "Fred"}],
                "@annotation": [{"ex:certainty": [{"@value": 0.8}]}]
              }]
            }
          }])
        },
        'reverse relationship inside annotation': {
          input: %({
            "@context": {
              "claims": {"@reverse": "ex:claims", "@type": "@id"}
            },
            "@id": "ex:bob",
            "ex:knows": {
              "@id": "ex:jane",
              "@annotation": {
                "ex:certainty": 0.8,
                "claims": "ex:sue"
              }
            }
          }),
          output: %([{
            "@id": "ex:bob",
            "ex:knows": [{
              "@id": "ex:jane",
              "@annotation": [{
                "ex:certainty": [{"@value": 0.8}],
                "@reverse": {
                  "ex:claims": [{"@id": "ex:sue"}]
                }
              }]
            }]
          }])
        }
      }.each do |title, params|
        it(title) { run_expand params.merge(rdfstar: true) }
      end
    end

    begin
      require 'nokogiri'
    rescue LoadError
    end
    require 'rexml/document'

    context "html" do
      %w[Nokogiri REXML].each do |impl|
        next unless Module.constants.map(&:to_s).include?(impl)

        context impl do
          let(:library) { impl.downcase.to_s.to_sym }

          {
            'Expands embedded JSON-LD script element': {
              input: %(
              <html>
                <head>
                  <script type="application/ld+json">
                  {
                    "@context": {
                      "foo": {"@id": "http://example.com/foo", "@container": "@list"}
                    },
                    "foo": [{"@value": "bar"}]
                  }
                  </script>
                </head>
              </html>),
              output: %([{
                "http://example.com/foo": [{"@list": [{"@value": "bar"}]}]
              }])
            },
            'Expands first script element': {
              input: %(
              <html>
                <head>
                  <script type="application/ld+json">
                  {
                    "@context": {
                      "foo": {"@id": "http://example.com/foo", "@container": "@list"}
                    },
                    "foo": [{"@value": "bar"}]
                  }
                  </script>
                  <script type="application/ld+json">
                  {
                    "@context": {"ex": "http://example.com/"},
                    "@graph": [
                      {"ex:foo": {"@value": "foo"}},
                      {"ex:bar": {"@value": "bar"}}
                    ]
                  }
                  </script>
                </head>
              </html>),
              output: %([{
                "http://example.com/foo": [{"@list": [{"@value": "bar"}]}]
              }])
            },
            'Expands targeted script element': {
              input: %(
              <html>
                <head>
                  <script id="first" type="application/ld+json">
                  {
                    "@context": {
                      "foo": {"@id": "http://example.com/foo", "@container": "@list"}
                    },
                    "foo": [{"@value": "bar"}]
                  }
                  </script>
                  <script id="second" type="application/ld+json">
                  {
                    "@context": {"ex": "http://example.com/"},
                    "@graph": [
                      {"ex:foo": {"@value": "foo"}},
                      {"ex:bar": {"@value": "bar"}}
                    ]
                  }
                  </script>
                </head>
              </html>),
              output: %([
                {"http://example.com/foo": [{"@value": "foo"}]},
                {"http://example.com/bar": [{"@value": "bar"}]}
              ]),
              base: "http://example.org/doc#second"
            },
            'Expands all script elements with extractAllScripts option': {
              input: %(
              <html>
                <head>
                  <script type="application/ld+json">
                  {
                    "@context": {
                      "foo": {"@id": "http://example.com/foo", "@container": "@list"}
                    },
                    "foo": [{"@value": "bar"}]
                  }
                  </script>
                  <script type="application/ld+json">
                  {
                    "@context": {"ex": "http://example.com/"},
                    "@graph": [
                      {"ex:foo": {"@value": "foo"}},
                      {"ex:bar": {"@value": "bar"}}
                    ]
                  }
                  </script>
                </head>
              </html>),
              output: %([
                {"http://example.com/foo": [{"@list": [{"@value": "bar"}]}]},
                {
                  "@graph": [{
                    "http://example.com/foo": [{"@value": "foo"}]
                  }, {
                    "http://example.com/bar": [{"@value": "bar"}]
                  }]
                }
              ]),
              extractAllScripts: true
            },
            'Expands multiple scripts where one is an array': {
              input: %(
              <html>
                <head>
                  <script type="application/ld+json">
                  {
                    "@context": {
                      "foo": {"@id": "http://example.com/foo", "@container": "@list"}
                    },
                    "foo": [{"@value": "bar"}]
                  }
                  </script>
                  <script type="application/ld+json">
                  [
                    {"@context": {"ex": "http://example.com/"}, "ex:foo": {"@value": "foo"}},
                    {"@context": {"ex": "http://example.com/"}, "ex:bar": {"@value": "bar"}}
                  ]
                  </script>
                </head>
              </html>),
              output: %([
                {"http://example.com/foo": [{"@list": [{"@value": "bar"}]}]},
                {"http://example.com/foo": [{"@value": "foo"}]},
                {"http://example.com/bar": [{"@value": "bar"}]}
              ]),
              extractAllScripts: true
            },
            'Errors no script element': {
              input: %(<html><head></head></html>),
              exception: JSON::LD::JsonLdError::LoadingDocumentFailed
            },
            'Expands as empty with no script element and extractAllScripts': {
              input: %(<html><head></head></html>),
              output: %([]),
              extractAllScripts: true
            },
            'Expands script element with HTML character references': {
              input: %(
              <html>
                <head>
                  <script type="application/ld+json">
                  {
                    "@context": {"@vocab": "http://example/"},
                    "foo": "&lt;&amp;&gt;"
                  }
                  </script>
                </head>
              </html>),
              output: %([{
                "http://example/foo": [{"@value": "&lt;&amp;&gt;"}]
              }])
            },
            'Expands embedded JSON-LD script element relative to document base': {
              input: %(
              <html>
                <head>
                  <script type="application/ld+json">
                  {
                    "@context": {
                      "foo": {"@id": "http://example.com/foo"}
                    },
                    "@id": "",
                    "foo": [{"@value": "bar"}]
                  }
                  </script>
                </head>
              </html>),
              output: %([{
                "@id": "http://example.org/doc",
                "http://example.com/foo": [{"@value": "bar"}]
              }]),
              base: "http://example.org/doc"
            },
            'Expands embedded JSON-LD script element relative to HTML base': {
              input: %(
              <html>
                <head>
                  <base href="http://example.org/base" />
                  <script type="application/ld+json">
                  {
                    "@context": {
                      "foo": {"@id": "http://example.com/foo"}
                    },
                    "@id": "",
                    "foo": [{"@value": "bar"}]
                  }
                  </script>
                </head>
              </html>),
              output: %([{
                "@id": "http://example.org/base",
                "http://example.com/foo": [{"@value": "bar"}]
              }]),
              base: "http://example.org/doc"
            },
            'Expands embedded JSON-LD script element relative to relative HTML base': {
              input: %(
              <html>
                <head>
                  <base href="base" />
                  <script type="application/ld+json">
                  {
                    "@context": {
                      "foo": {"@id": "http://example.com/foo"}
                    },
                    "@id": "",
                    "foo": [{"@value": "bar"}]
                  }
                  </script>
                </head>
              </html>),
              output: %([{
                "@id": "http://example.org/base",
                "http://example.com/foo": [{"@value": "bar"}]
              }]),
              base: "http://example.org/doc"
            },
            'Errors if no element found at target': {
              input: %(
              <html>
                <head>
                  <script id="first" type="application/ld+json">
                  {
                    "@context": {
                      "foo": {"@id": "http://example.com/foo", "@container": "@list"}
                    },
                    "foo": [{"@value": "bar"}]
                  }
                  </script>
                  <script id="second" type="application/ld+json">
                  {
                    "@context": {"ex": "http://example.com/"},
                    "@graph": [
                      {"ex:foo": {"@value": "foo"}},
                      {"ex:bar": {"@value": "bar"}}
                    ]
                  }
                  </script>
                </head>
              </html>),
              base: "http://example.org/doc#third",
              exception: JSON::LD::JsonLdError::LoadingDocumentFailed
            },
            'Errors if targeted element is not a script element': {
              input: %(
              <html>
                <head>
                  <pre id="first" type="application/ld+json">
                  {
                    "@context": {
                      "foo": {"@id": "http://example.com/foo", "@container": "@list"}
                    },
                    "foo": [{"@value": "bar"}]
                  }
                  </pre>
                </head>
              </html>),
              base: "http://example.org/doc#first",
              exception: JSON::LD::JsonLdError::LoadingDocumentFailed
            },
            'Errors if targeted element does not have type application/ld+json': {
              input: %(
              <html>
                <head>
                  <script id="first" type="application/json">
                  {
                    "@context": {
                      "foo": {"@id": "http://example.com/foo", "@container": "@list"}
                    },
                    "foo": [{"@value": "bar"}]
                  }
                  </script>
                </head>
              </html>),
              base: "http://example.org/doc#first",
              exception: JSON::LD::JsonLdError::LoadingDocumentFailed
            },
            'Errors if uncommented script text contains comment': {
              input: %(
              <html>
                <head>
                  <script type="application/ld+json">
                  <!--
                  {
                    "@context": {
                      "foo": {"@id": "http://example.com/foo", "@container": "@list"}
                    },
                    "foo": [{"@value": "<!-- -->"}]
                  }
                  -->
                  </script>
                </head>
              </html>),
              exception: JSON::LD::JsonLdError::InvalidScriptElement,
              not: :rexml
            },
            'Errors if end comment missing': {
              input: %(
              <html>
                <head>
                  <script type="application/ld+json">
                  <!--
                  {
                    "@context": {
                      "foo": {"@id": "http://example.com/foo", "@container": "@list"}
                    },
                    "foo": [{"@value": "bar"}]
                  }
                  </script>
                </head>
              </html>),
              exception: JSON::LD::JsonLdError::InvalidScriptElement,
              not: :rexml
            },
            'Errors if start comment missing': {
              input: %(
              <html>
                <head>
                  <script type="application/ld+json">
                  {
                    "@context": {
                      "foo": {"@id": "http://example.com/foo", "@container": "@list"}
                    },
                    "foo": [{"@value": "bar"}]
                  }
                  -->
                  </script>
                </head>
              </html>),
              exception: JSON::LD::JsonLdError::InvalidScriptElement
            },
            'Errors if uncommented script is not valid JSON': {
              input: %(
              <html>
                <head>
                  <script type="application/ld+json">
                  foo
                  </script>
                </head>
              </html>),
              exception: JSON::LD::JsonLdError::InvalidScriptElement
            }
          }.each do |title, params|
            it(title) do
              skip "rexml" if params[:not] == library
              params = params.merge(input: StringIO.new(params[:input]))
              params[:input].send(:define_singleton_method, :content_type) { "text/html" }
              run_expand params.merge(validate: true, library: library)
            end
          end
        end
      end
    end

    context "deprectaions" do
      {
        'blank node property': {
          input: %({"_:bn": "value"}),
          output: %([{"_:bn": [{"@value": "value"}]}])
        }
      }.each do |name, params|
        it "deprecation on #{name} when validating" do
          run_expand(params.merge(validate: true, write: "[DEPRECATION]"))
        end

        it "no deprecation on #{name} when not validating" do
          run_expand(params.merge(validate: false))
        end
      end
    end

    context "exceptions" do
      {
        'non-null @value and null @type': {
          input: %({"http://example.com/foo": {"@value": "foo", "@type": null}}),
          exception: JSON::LD::JsonLdError::InvalidTypeValue
        },
        'non-null @value and null @language': {
          input: %({"http://example.com/foo": {"@value": "foo", "@language": null}}),
          exception: JSON::LD::JsonLdError::InvalidLanguageTaggedString
        },
        'value with null language': {
          input: %({
            "@context": {"@language": "en"},
            "http://example.org/nolang": {"@value": "no language", "@language": null}
          }),
          exception: JSON::LD::JsonLdError::InvalidLanguageTaggedString
        },
        'colliding keywords': {
          input: %({
            "@context": {
              "id": "@id",
              "ID": "@id"
            },
            "id": "http://example/foo",
            "ID": "http://example/bar"
          }),
          exception: JSON::LD::JsonLdError::CollidingKeywords
        },
        '@language and @type': {
          input: %({
            "ex:p": {
              "@value": "v",
              "@type": "ex:t",
              "@language": "en"
            }
          }),
          exception: JSON::LD::JsonLdError::InvalidValueObject,
          processingMode: 'json-ld-1.1'
        },
        '@direction and @type': {
          input: %({
            "ex:p": {
              "@value": "v",
              "@type": "ex:t",
              "@direction": "rtl"
            }
          }),
          exception: JSON::LD::JsonLdError::InvalidValueObject,
          processingMode: 'json-ld-1.1'
        }
      }.each do |title, params|
        it(title) { run_expand params }
      end
    end

    context "problem cases" do
      {
        'toRdf/0118': {
          input: %({
            "@context": {"term": "_:term", "termId": { "@id": "term", "@type": "@id" }},
            "termId": "term:AppendedToBlankNode"
          }),
          output: %([{
            "_:term": [{"@id": "_:termAppendedToBlankNode"}]
          }])
        }
      }.each do |title, params|
        it(title) { run_expand params }
      end
    end
  end

  def run_expand(params)
    input = params[:input]
    output = params[:output]
    params[:base] ||= nil
    input = JSON.parse(input) if input.is_a?(String)
    output = JSON.parse(output) if output.is_a?(String)
    pending params.fetch(:pending, "test implementation") unless input
    if params[:exception]
      expect { JSON::LD::API.expand(input, **params) }.to raise_error(params[:exception])
    else
      jld = nil
      if params[:write]
        expect { jld = JSON::LD::API.expand(input, logger: logger, **params) }.to write(params[:write]).to(:error)
      else
        expect { jld = JSON::LD::API.expand(input, logger: logger, **params) }.not_to write.to(:error)
      end
      expect(jld).to produce_jsonld(output, logger)

      # Also expect result to produce itself
      expect(output).to produce_jsonld(output, logger)
    end
  end
end
