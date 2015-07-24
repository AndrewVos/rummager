require "elasticsearch/base_worker"

module CustomElasticsearch
  class AmendWorker < BaseWorker
    forward_to_failure_queue

    def perform(index_name, document_link, updates)
      logger.info "Amending document '#{document_link}' in '#{index_name}'"
      logger.info "Amending fields #{updates.keys.join(', ')}"
      logger.debug "Amendments: #{updates}"
      begin
        index(index_name).amend(document_link, updates)
      rescue CustomElasticsearch::IndexLocked
        logger.info "Index #{index_name} is locked; rescheduling"
        self.class.perform_in(LOCK_DELAY, index_name, document_link, updates)
      end
    end
  end
end
