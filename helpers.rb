# encoding: utf-8
require "solr_wrapper"

module Helpers
  HIGHLIGHT_START = SolrWrapper::HIGHLIGHT_START
  HIGHLIGHT_END   = SolrWrapper::HIGHLIGHT_END

  include Rack::Utils
  alias_method :h, :escape_html

  def proposition
    settings.slimmer_headers[:proposition]
  end

  def capped_search_set_size
    [@results.count, (settings.top_results + settings.max_more_results)].min
  end

  def base_url
    return "https://www.gov.uk" if ENV['FACTER_govuk_platform'] == 'production'
    "https://www.#{ENV['FACTER_govuk_platform']}.alphagov.co.uk"
  end

  def top_results
    results = non_recommended_results[0..(settings.top_results-1)]
    results.empty? ? nil : results
  end

  def more_results
    non_recommended_results[settings.top_results..(settings.top_results + settings.max_more_results-1)]
  end

  def recommended_results
    @results.select { |r| r.format == settings.recommended_format }[0, settings.max_recommended_results]
  end

  def non_recommended_results
    @results.select { |r| r.format != settings.recommended_format }
  end

  def pluralize(singular, plural)
    @results.count == 1 ? singular : plural
  end

  def formatted_format_name(name)
    alt = settings.format_name_alternatives[name]
    return alt if alt
    return "#{name.capitalize}s"
  end

  def include(name)
    begin
      File.open("views/_#{name}.html").read
    rescue Errno::ENOENT
    end
  end

  def simple_json_result(ok)
    content_type :json
    if ok
      result = "OK"
    else
      result = "error"
      status 500
    end
    JSON.dump("result" => result)
  end

  def apply_highlight(s)
    s = s.strip
    return "" if s.empty?
    just_text = s.gsub(/#{HIGHLIGHT_START}|#{HIGHLIGHT_END}/, "")
    [ just_text.match(/\A[[:upper:]]/) ? "" : "… ",
      s.gsub(HIGHLIGHT_START, %{<strong class="highlight">}).
        gsub(HIGHLIGHT_END, %{</strong>}),
      just_text.match(/[\.\?!]\z/) ? "" : " …"
    ].join
  end

  def map_section_name(slug)
    map = {
      "life-in-the-uk" => "Life in the UK",
      "housing-benefits-grants-and-schemes" => "Housing benefits, grants and schemes",
      "work-related-benefits-and-schemes" => "Work-related benefits and schemes",
      "buying-selling-a-vehicle" => "Buying/selling a vehicle",
      "owning-a-car-motorbike" => "Owning a car/motorbike",
      "council-and-housing-association-homes" => "Council and housing association homes",
      "animals-food-and-plants" => "Animals, food and plants",
      "mot" => "MOT"
    }
    return map[slug] ? map[slug] : false  
  end

  def humanize_section_name(slug)
    slug.gsub('-', ' ').capitalize
  end

  def formatted_section_name(slug)
    map_section_name(slug) ? map_section_name(slug) : humanize_section_name(slug)
  end

end

class HelperAccessor
  include Helpers
end
