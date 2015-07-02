namespace :publishing_api do

  task :register_content_items do
    require 'plek'
    require 'gds_api/publishing_api'
    publishing_api = GdsApi::PublishingApi.new(Plek.find('publishing-api'))

    base_details = {
      "title" => "Something",
      "format" => "something",
      "publishing_app" => "rummager",
      "public_updated_at" => Time.now.utc.iso8601,
      "update_type" => "republish",
    }
    specific_details = {
      "/search" => {
        "rendering_app" => "frontend",
        "routes" => [
          {"path" => "/search", "type" => "exact"},
          {"path" => "/search.json", "type" => "exact"},
        ],
      },
      "/sitemap.xml" => {
        "rendering_app" => "rummager",
        "routes" => [{"path" => "/sitemap.xml", "type" => "exact"}],
      },
      "/sitemaps" => {
        "rendering_app" => "rummager",
        "routes" => [{"path" => "/sitemaps", "type" => "prefix"}],
      },
    }
    specific_details.each do |base_path, details|
      item_details = base_details.merge(details)

      pute "Registering #{base_path}"
      publishing_api.put_content_item(base_path, item_details)
    end
  end
end
