module QueryComponents
  class BaseComponent
    include CustomElasticsearch::Escaping

    attr_reader :params

    def initialize(params = {})
      @params = params
    end

  protected

    def search_term
      params[:query]
    end

    def debug
      params[:debug] || {}
    end
  end
end
