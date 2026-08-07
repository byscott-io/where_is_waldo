# frozen_string_literal: true

module WhereIsWaldo
  # APM (New Relic) integration seam.
  #
  # The gem takes NO hard dependency on newrelic_rpm. Every method here no-ops
  # unless a supported agent is loaded in the host app, so a consumer without
  # New Relic pays nothing and nothing breaks.
  #
  # Why this exists: ActionCable dispatches each client action through New
  # Relic's ActionCableSubscriber, which starts one APM transaction per
  # `perform_action`. Presence heartbeats are the highest-volume, least
  # interesting action Waldo has — one per open tab per heartbeat interval,
  # uniformly fast — so left alone they dominate transaction throughput and
  # flatten the host app's average response time while telling operators nothing
  # the presence store can't already answer. `ignoring_transaction` keeps them
  # out of APM's headline numbers without hiding failures.
  #
  # (The companion half of this problem — the agent pinning the WebSocket
  # upgrade transaction onto pooled ActionCable worker threads — is a general
  # newrelic_rpm x ActionCable defect, not Waldo's to fix here. Host apps carry
  # that shim until the agent resets pooled-thread state itself.)
  #
  # Scope: this handles New Relic ONLY. The underlying exposure is agent-general
  # — any APM/tracer that opens a transaction per `perform_action` (Datadog,
  # Scout, AppSignal, Skylight, Sentry, OpenTelemetry) sees the same heartbeat
  # flood, and several share the same pooled-thread context-leak. Waldo doesn't
  # cause that (it spawns no threads and patches nothing global); its heartbeat
  # volume amplifies whatever the host's agent already does. Detection is
  # isolated in `agent` so another vendor can be added there without touching
  # callers.
  module Apm
    module_function

    # The New Relic agent module, or nil when newrelic_rpm isn't loaded (or is
    # too old to expose the API we use). Isolated behind one method so specs can
    # drive both the present and absent paths without defining a global
    # ::NewRelic constant.
    def agent
      return nil unless defined?(::NewRelic::Agent)
      return nil unless ::NewRelic::Agent.respond_to?(:ignore_transaction)

      ::NewRelic::Agent
    end

    # Run a unit of work without letting it surface as its own APM transaction,
    # and return the block's value.
    #
    # A plain `yield` when there's no agent, or when the host has opted out via
    # `config.ignore_heartbeat_apm = false` — in either case the transaction is
    # reported normally.
    #
    # New Relic's `Transaction#ignore!` makes `#finish` skip `commit!`, and
    # `commit!` is where transaction-attached exceptions are harvested
    # (`record_exceptions`). So ignoring on its own would ALSO swallow a
    # heartbeat failure. We hand any exception straight to the error collector —
    # which reports immediately rather than at commit — and re-raise, so the
    # caller's own error handling is unchanged.
    def ignoring_transaction
      nr = agent
      return yield unless nr && WhereIsWaldo.config.ignore_heartbeat_apm

      nr.ignore_transaction

      begin
        yield
      rescue StandardError => e
        nr.instance&.error_collector&.notice_error(e)
        raise
      end
    end
  end
end
