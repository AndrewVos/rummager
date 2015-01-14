# Fetch example values for facets
class FacetExampleFetcher
  def initialize(index, es_response, params, search_builder)
    @index = index
    @response_facets = es_response["facets"]
    @params = params
    @search_builder = search_builder
  end

  # Fetch all requested example facet values
  # Returns {field_name => {facet_value => {total: count, examples: [{field: value}, ...]}}}
  # ie: a hash keyed by field name, containing hashes keyed by facet value with
  # values containing example information for the value.
  def fetch
    facets = @params[:facets]
    if facets.nil? || @response_facets.nil?
      return {}
    end
    result = {}
    facets.each do |field_name, facet_params|
      examples = facet_params[:examples]
      if examples > 0
        result[field_name] = fetch_for_field(field_name, facet_params)
      end
    end
    result
  end

private
  def fetch_for_field(field_name, facet_params)
    example_count = facet_params[:examples]
    example_fields = facet_params[:example_fields]
    scope = facet_params[:example_scope]

    if scope == :query
      query = @search_builder.query
      filter = @search_builder.filter
    else
      query = nil
      filter = nil
    end

    facet_options = @response_facets.fetch(field_name, {}).fetch("terms", [])

    slugs = facet_options.map { |option|
      option["term"]
    }
    if slugs.empty?
      {}
    else
      fetch_by_slug(field_name, slugs, example_count, example_fields, query, filter)
    end
  end

  def facet_example_searches(field_name, slugs, example_count, example_fields, query, query_filter)
    slugs.map { |slug|
      if query_filter.nil?
        filter = { term: { field_name => slug } }
      else
        filter = { and: [
          { term: { field_name => slug } },
          query_filter,
        ]}
      end
      {
        query: {
          filtered: {
            query: query,
            filter: filter,
          }
        },
        size: example_count,
        fields: example_fields,
        sort: [ { popularity: { order: :desc } } ],
      }
    }
  end

  # Fetch facet examples for a set of slugs
  def fetch_by_slug(field_name, slugs, example_count, example_fields, query, filter)
    searches = facet_example_searches(field_name, slugs, example_count, example_fields, query, filter)
    responses = @index.msearch(searches)
    response_list = responses["responses"]
    result = {}
    slugs.zip(response_list) { |slug, response|
      hits = response["hits"]
      result[slug] = {
        total: hits["total"],
        examples: hits["hits"].map { |hit| hit["fields"] },
      }
    }
    result
  end
end
