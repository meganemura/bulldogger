# frozen_string_literal: true

module Bulldogger
  # Turns an arbitrary Ruby value into a bounded, JSON-safe String.
  # Bounded because a snapshot is written on every failing test, so an
  # unbounded value (a huge String, a deep object graph) would make
  # capture itself expensive. Safe because `inspect` is arbitrary user
  # code: it can raise, and the object it runs on may descend from
  # BasicObject, where even `#class` is undefined.
  class Formatter
    MAX_ELEMENTS = 10

    def initialize(config:, redactor:)
      @max_value_length = config.max_value_length
      @redactor = redactor
    end

    # Returns the per-local entry shape: {"value" => str} normally, plus
    # "truncated"/"original_length" when the final string was too long.
    # Those extra keys are the record that something was cut -- they
    # must never appear on a value that was not, so a reader can trust
    # their absence.
    def format(value)
      truncate_entry(render(value))
    end

    # Returns just the (possibly truncated) String, for JSON slots that
    # hold a plain string rather than a {"value"=>...} entry -- a
    # frame's "self", for example.
    def format_self(value)
      format(value)["value"]
    end

    private

    def render(value)
      case value
      when Array
        render_array(value)
      when Hash
        render_hash(value)
      else
        safe_inspect(value)
      end
    end

    def render_array(array)
      kept = array.first(MAX_ELEMENTS)
      parts = kept.map { |element| render_nested(element) }
      parts << "…" if array.size > kept.size
      "[#{parts.join(', ')}]"
    end

    def render_hash(hash)
      kept = hash.first(MAX_ELEMENTS)
      parts = kept.map { |key, value| render_pair(key, value) }
      parts << "…" if hash.size > kept.size
      "{#{parts.join(', ')}}"
    end

    def render_pair(key, value)
      key_repr = render_nested(key)
      value_repr = @redactor.redact_key?(key) ? '"[REDACTED]"' : render_nested(value)
      "#{key_repr} => #{value_repr}"
    end

    # One level of expansion only: an Array/Hash found *inside* an
    # Array/Hash is shown as a placeholder, not walked further. Without
    # this, a self-referential or very deep structure could make a
    # single value's rendering unbounded even with max_value_length
    # trimming the end result.
    def render_nested(value)
      case value
      when Array then "[…]"
      when Hash then "{…}"
      else safe_inspect(value)
      end
    end

    def safe_inspect(value)
      value.inspect
    rescue Exception => e # rubocop:disable Lint/RescueException
      "#<#{safe_class_name(value)} (inspect raised #{e.class})>"
    end

    def safe_class_name(value)
      klass = value.class
      klass.respond_to?(:name) ? (klass.name || klass.to_s) : klass.to_s
    rescue Exception # rubocop:disable Lint/RescueException
      "Object"
    end

    def truncate_entry(str)
      return { "value" => str } if str.length <= @max_value_length

      {
        "value" => str[0, @max_value_length] + "…",
        "truncated" => true,
        "original_length" => str.length
      }
    end
  end
end
