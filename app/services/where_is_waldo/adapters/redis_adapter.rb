# frozen_string_literal: true

module WhereIsWaldo
  module Adapters
    class RedisAdapter < BaseAdapter
      def connect(session_id:, subject_id:, metadata: {})
        now = Time.current.to_i

        presence_data = {
          session_id: session_id,
          subject_id: subject_id,
          connected_at: now,
          last_heartbeat: now,
          tab_visible: true,
          subject_active: true,
          last_activity: now,
          metadata: metadata
        }

        redis.multi do |tx|
          # Store session data
          tx.set(session_key(session_id), presence_data.to_json, ex: ttl)

          # Add to online subjects sorted set with timestamp as score
          tx.zadd(online_subjects_key, now, subject_id)

          # Add to subject's sessions set
          tx.sadd(subject_sessions_key(subject_id), session_id)

          # Map session to subject for reverse lookup
          tx.set(session_subject_key(session_id), subject_id, ex: ttl)
        end

        true
      rescue StandardError => e
        Rails.logger.error "[WhereIsWaldo] Redis connect failed: #{e.message}"
        false
      end

      def disconnect(session_id: nil, subject_id: nil)
        if session_id
          disconnect_session(session_id)
        elsif subject_id
          disconnect_subject(subject_id)
        end

        true
      rescue StandardError => e
        Rails.logger.error "[WhereIsWaldo] Redis disconnect failed: #{e.message}"
        false
      end

      def heartbeat(session_id:, tab_visible: true, subject_active: true, last_activity_at: nil, metadata: {})
        data = get_presence_data(session_id)
        return false unless data

        now = Time.current.to_i
        data["last_heartbeat"] = now
        data["tab_visible"] = tab_visible
        data["subject_active"] = subject_active
        # Update last_activity: use JS timestamp if provided, otherwise use current time when active
        if last_activity_at
          data["last_activity"] = (last_activity_at / 1000.0).to_i
        elsif subject_active
          data["last_activity"] = now
        end
        data["metadata"] = data["metadata"].merge(metadata) if metadata.present?

        redis.multi do |tx|
          tx.set(session_key(session_id), data.to_json, ex: ttl)
          tx.zadd(online_subjects_key, now, data["subject_id"])
        end

        true
      rescue StandardError => e
        Rails.logger.error "[WhereIsWaldo] Redis heartbeat failed: #{e.message}"
        false
      end

      def online_subject_ids(timeout: nil)
        threshold = Time.current.to_i - (timeout || default_timeout)

        # Get subject IDs with heartbeat after threshold
        redis.zrangebyscore(online_subjects_key, threshold, "+inf").map(&:to_i)
      end

      def sessions_for_subject(subject_id)
        session_ids = redis.smembers(subject_sessions_key(subject_id))

        session_ids.filter_map do |sid|
          data = get_presence_data(sid)
          build_presence_hash(data) if data
        end
      end

      def sessions_for_subjects(subject_ids, timeout: nil)
        ids = Array(subject_ids).compact.uniq
        return {} if ids.empty?

        threshold = Time.current.to_i - (timeout || default_timeout)
        ids.each_with_object({}) do |sid, memo|
          session_ids = redis.smembers(subject_sessions_key(sid))
          live = session_ids.filter_map do |cid|
            data = get_presence_data(cid)
            next unless data && data["last_heartbeat"].to_i >= threshold

            build_presence_hash(data)
          end
          memo[sid] = live if live.any?
        end
      end

      def session_status(session_id)
        data = get_presence_data(session_id)
        return nil unless data

        build_presence_hash(data)
      end

      def cleanup(timeout: nil)
        threshold = Time.current.to_i - (timeout || default_timeout)
        cleaned = 0

        # Get stale subject IDs
        stale_subject_ids = redis.zrangebyscore(online_subjects_key, "-inf", threshold)

        stale_subject_ids.each do |subject_id|
          # Check if any sessions are still active
          session_ids = redis.smembers(subject_sessions_key(subject_id))
          all_stale = session_ids.all? do |sid|
            data = get_presence_data(sid)
            !data || data["last_heartbeat"].to_i < threshold
          end

          if all_stale
            disconnect_subject(subject_id)
            cleaned += 1
          end
        end

        # Remove stale entries from sorted set
        redis.zremrangebyscore(online_subjects_key, "-inf", threshold)

        cleaned
      end

      private

      def redis
        config.redis_client || raise("Redis client not configured")
      end

      def ttl
        (config.timeout * 1.5).to_i # Give some buffer beyond timeout
      end

      def key_prefix
        config.redis_prefix || "where_is_waldo"
      end

      def session_key(session_id)
        "#{key_prefix}:session:#{session_id}"
      end

      def online_subjects_key
        "#{key_prefix}:online_subjects"
      end

      def subject_sessions_key(subject_id)
        "#{key_prefix}:subject:#{subject_id}:sessions"
      end

      def session_subject_key(session_id)
        "#{key_prefix}:session_subject:#{session_id}"
      end

      def get_presence_data(session_id)
        json = redis.get(session_key(session_id))
        return nil unless json

        JSON.parse(json)
      end

      def disconnect_session(session_id)
        data = get_presence_data(session_id)
        return unless data

        subject_id = data["subject_id"]

        redis.multi do |tx|
          tx.del(session_key(session_id))
          tx.srem(subject_sessions_key(subject_id), session_id)
          tx.del(session_subject_key(session_id))
        end

        # If no more sessions for this subject, remove from online set
        remaining = redis.scard(subject_sessions_key(subject_id))
        redis.zrem(online_subjects_key, subject_id) if remaining.zero?
      end

      def disconnect_subject(subject_id)
        session_ids = redis.smembers(subject_sessions_key(subject_id))
        session_ids.each { |sid| disconnect_session(sid) }
        redis.zrem(online_subjects_key, subject_id)
      end

      def build_presence_hash(data)
        {
          session_id: data["session_id"],
          subject_id: data["subject_id"],
          connected_at: Time.zone.at(data["connected_at"]),
          last_heartbeat: Time.zone.at(data["last_heartbeat"]),
          last_activity: data["last_activity"] ? Time.zone.at(data["last_activity"]) : nil,
          tab_visible: data["tab_visible"],
          subject_active: data["subject_active"],
          metadata: data["metadata"] || {},
          subject: nil # Redis adapter doesn't eager load subjects
        }
      end
    end
  end
end
