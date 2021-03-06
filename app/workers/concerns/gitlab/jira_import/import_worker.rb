# frozen_string_literal: true

module Gitlab
  module JiraImport
    module ImportWorker
      extend ActiveSupport::Concern

      included do
        include ApplicationWorker
        include Gitlab::JiraImport::QueueOptions
      end

      def perform(project_id)
        project = Project.find_by(id: project_id) # rubocop: disable CodeReuse/ActiveRecord

        return unless can_import?(project)

        import(project)
      end

      private

      def import(project)
        raise NotImplementedError
      end

      def can_import?(project)
        return false unless project
        return false unless project.jira_issues_import_feature_flag_enabled?

        project.latest_jira_import&.started?
      end
    end
  end
end
