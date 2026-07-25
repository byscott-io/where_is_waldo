# frozen_string_literal: true

module WhereIsWaldo
  module ApplicationCable
    class Connection < ActionCable::Connection::Base
      identified_by :waldo_subject_id, :waldo_session_id

      def connect
        authenticate_connection
      end

      private

      def authenticate_connection
        auth_proc = WhereIsWaldo.config.authenticate_proc

        if auth_proc
          # Use custom authentication
          result = auth_proc.call(request)

          if result.is_a?(Hash)
            self.waldo_subject_id = result[:subject_id]
            self.waldo_session_id = result[:session_id] || generate_session_id
          elsif result
            # If proc returns truthy non-hash, use it as subject_id
            self.waldo_subject_id = result
            self.waldo_session_id = generate_session_id
          else
            reject_unauthorized_connection
          end
        else
          # No authenticate_proc configured. The only remaining identity source
          # is client-controlled params, which must NEVER authenticate a real
          # connection (a client could pass ?subject_id=<anyone> and impersonate
          # them). Permit it ONLY in local dev/test as a convenience; fail closed
          # everywhere else. Production apps must configure `authenticate_proc`
          # (or identify the connection themselves, e.g. via JwtConnection).
          if Rails.env.local?
            self.waldo_subject_id = request.params[:subject_id]
            self.waldo_session_id = request.params[:session_id] || generate_session_id
          end

          reject_unauthorized_connection unless waldo_subject_id
        end
      end

      def generate_session_id
        SecureRandom.uuid
      end
    end
  end
end
