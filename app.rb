%w[ lib ].each do |path|
  $:.unshift path unless $:.include?(path)
end

require 'sinatra'
require 'slimmer'
require 'erubis'
require 'json'
require 'csv'

require 'popular_items'
require 'document'
require 'section'
require 'utils'
require 'solr_wrapper'
require 'slimmer_headers'

require_relative 'helpers'
require_relative 'config'

def solr
  @solr ||= SolrWrapper.new(DelSolr::Client.new(settings.solr), settings.recommended_format)
end

helpers do
  include Helpers
end

before do
  headers SlimmerHeaders.headers(settings.slimmer_headers)
end

def prefixed_path(path)
  path_prefix = settings.router[:path_prefix]
  raise "Path prefix must start with /" unless path_prefix.blank? || path_prefix =~ /^\//
  "#{path_prefix}#{path}"
end

get prefixed_path("/search") do
  if params['q'].nil? or params['q'].strip == ''
    @page_section = "Search"
    @page_section_link = "/search"
    @page_title = "Search | GOV.UK"
    return erb(:no_search_term)
  end
  @query = params['q']
  @results = solr.search(@query)

  if request.accept.include?("application/json")
    content_type :json
    JSON.dump(@results.map { |r| r.to_hash.merge(highlight: r.highlight) })
  else
    @page_section = "Search"
    @page_section_link = "/search"
    @page_title = "#{@query} | Search | GOV.UK"

    if @results.any?
      erb(:search)
    else
      erb(:no_search_results)
    end
  end
end

get prefixed_path("/preload-autocomplete") do
  # Eventually this is likely to be a list of commonly searched for terms
  # so searching for those is really fast. For the beta, this is just a list
  # of all terms.
  results = solr.autocomplete_cache rescue []
  content_type :json
  JSON.dump(results.map { |r| r.to_hash })
end

get prefixed_path("/autocomplete") do
  query = params['q'] or return '[]'
  results = solr.complete(query) rescue []
  content_type :json
  JSON.dump(results.map { |r| r.to_hash })
end

get prefixed_path("/sitemap.xml") do
  # Site maps can have up to 50,000 links in them.
  # We use one for / so we can have up to 49,999 others.
  documents = solr.all_documents limit: 49_999
  builder do |xml|
    xml.instruct!
    xml.urlset(xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9") do
      xml.url do
	xml.loc "#{base_url}#{prefixed_path("/")}"
      end
      documents.each do |document|
	xml.url do
	  url = document.link
          url = "#{base_url}#{url}" if url =~ /^\//
	  xml.loc url
	end
      end
    end
  end
end

if settings.router[:path_prefix].empty?
  get prefixed_path("/browse") do
    @results = solr.facet('section')
    @page_section = "Browse"
    @page_section_link = "/browse"
    @page_title = "Browse | GOV.UK"
    erb(:sections)
  end

  get prefixed_path("/browse/:section") do
    section = params[:section].gsub(/[^a-z0-9\-_]+/, '-')
    halt 404 unless section == params[:section]
    results = solr.section(section)
    halt 404 if results.empty?

    popular_items = PopularItems.new(settings.popular_items_file)
    @popular = popular_items.select_from(params[:section], results)
    
    File.open('/tmp/results.txt', 'w') {|f| f.write results.inspect}
    @results = results.group_by { |result| result.subsection }

    @section = Section.new(section)
    @page_section = @section.name
    @page_section_link = @section.path
    @page_title = "#{@section.name} | GOV.UK"
    erb(:section)
  end
end

post prefixed_path("/documents") do
  request.body.rewind
  documents = [JSON.parse(request.body.read)].flatten.map { |hash|
    Document.from_hash(hash)
  }

  boosts = {}
  CSV.foreach(settings.boost_csv) { |row|
    link, phrases = row
    boosts[link] = phrases
  }

  better_documents = boost_documents(documents, boosts)

  simple_json_result(solr.add(better_documents))
end

post prefixed_path("/commit") do
  simple_json_result(solr.commit)
end

delete prefixed_path("/documents/*") do
  simple_json_result(solr.delete(params["splat"].first))
end
