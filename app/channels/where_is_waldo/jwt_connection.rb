# frozen_string_literal: true

module WhereIsWaldo
  # Turnkey ActionCable connection auth for corebyscott apps. The cable client
  # appends the user's JWT as `?token=...`; this decodes it via
  # Corebyscott::JwtService and identifies the connection by the authenticated
  # user (the presence subject), the JWT's container (cid), and session (jti).
  #
  #   # app/channels/application_cable/connection.rb
  #   module ApplicationCable
  #     class Connection < ActionCable::Connection::Base
  #       include WhereIsWaldo::JwtConnection
  #     end
  #   end
  #
  # The subject model comes from WhereIsWaldo.configuration.subject_class
  # (e.g. "User"); the container class from Corebyscott.config. Opt-in: only
  # include it in apps that authenticate with corebyscott JWTs.
  module JwtConnection
    extend ActiveSupport::Concern

    included do
      identified_by :current_user, :current_container, :session_id
    end

    def connect
      self.current_user = wiw_verified_user
      self.current_container = wiw_container
      self.session_id = wiw_session_id
    end

    private

    # Memoized decode of the ?token= param. nil when absent/invalid.
    def wiw_token_payload
      return @wiw_token_payload if defined?(@wiw_token_payload)

      token = request.params[:token]
      @wiw_token_payload =
        if token.present? && defined?(::Corebyscott::JwtService)
          begin
            ::Corebyscott::JwtService.decode(token, touch_last_used: false)
          rescue StandardError
            nil
          end
        end
    end

    def wiw_verified_user
      payload = wiw_token_payload
      reject_unauthorized_connection unless payload

      user = wiw_resolve_subject(payload)
      reject_unauthorized_connection unless user

      user
    end

    # `sub` is not always this app's primary key.
    #
    # Under corebyscott's :identity_server mode it is the identity server's
    # UUID, so find_by(id:) matches nothing and EVERY cable connection is
    # rejected -- silently, because a rejected connection is indistinguishable
    # from a client that never subscribed. Core's resolver maps the UUID through
    # users.identity_id, the same path its HTTP auth takes, so cable and request
    # auth cannot disagree about who someone is.
    #
    # Only used when the configured subject IS core's user class. An app whose
    # presence subject is some other model keeps the primary-key lookup, since
    # core's resolver would hand back a user rather than that subject.
    def wiw_resolve_subject(payload)
      klass = WhereIsWaldo.configuration.subject_class_constant

      if wiw_identity_mode? && klass && klass == wiw_core_user_class
        return ::Corebyscott::IdentityResolver.resolve(payload)
      end

      klass&.find_by(id: payload["sub"] || payload[:sub])
    end

    def wiw_identity_mode?
      defined?(::Corebyscott::IdentityResolver) &&
        ::Corebyscott.respond_to?(:config) &&
        ::Corebyscott.config.respond_to?(:auth_mode) &&
        ::Corebyscott.config.auth_mode.to_s == "identity_server"
    end

    def wiw_core_user_class
      return nil unless ::Corebyscott.config.respond_to?(:user_class_constant)

      ::Corebyscott.config.user_class_constant
    end

    # Optional container scoping from the JWT's `cid` claim. nil when the app
    # doesn't scope tokens to a container, or corebyscott isn't present.
    def wiw_container
      payload = wiw_token_payload
      return nil unless payload && current_user
      return nil unless defined?(::Corebyscott)

      cid = payload["cid"] || payload[:cid]
      return nil if cid.blank?

      container_class = begin
        ::Corebyscott.config.container_class&.constantize
      rescue StandardError
        nil
      end
      container_class&.find_by(id: cid)
    end

    def wiw_session_id
      payload = wiw_token_payload
      payload&.dig("jti") || payload&.dig(:jti) || SecureRandom.uuid
    end
  end
end
