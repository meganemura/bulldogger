# frozen_string_literal: true

require "json"

module Bulldogger
  module Probe
    # Compares two probe evidence files for behavior-preservation:
    # "did this refactor change what the probed methods actually do."
    #
    # Compares *shape* (classes seen, nil_count, raised_exits, calls,
    # the set of callers, parameters), not raw sample values, because
    # the default `inspect` embeds an object's memory address (e.g.
    # `#<Order:0x000000012a>`), so two probes of *identical*,
    # unchanged code would otherwise report differences on every run.
    # Samples are still diffed as a secondary signal, but only after
    # normalizing `0x[0-9a-f]+` out of them for exactly this reason.
    module Comparator
      HEX_ADDRESS = /0x[0-9a-f]+/i

      module_function

      def compare(path_a, path_b)
        a = JSON.parse(File.read(path_a))
        b = JSON.parse(File.read(path_b))
        differences = []
        compare_methods(a["methods"] || {}, b["methods"] || {}, differences)
        { "identical" => differences.empty?, "differences" => differences }
      end

      def compare_methods(methods_a, methods_b, differences)
        (methods_a.keys | methods_b.keys).each do |label|
          ma = methods_a[label]
          mb = methods_b[label]
          if ma.nil? || mb.nil?
            differences << "#{label}: only present in #{ma.nil? ? 'b' : 'a'}"
            next
          end

          compare_method(label, ma, mb, differences)
        end
      end

      def compare_method(label, ma, mb, differences)
        add_diff(differences, label, "calls", ma["calls"], mb["calls"])
        add_diff(differences, label, "raised_exits", ma["raised_exits"], mb["raised_exits"])
        add_diff(differences, label, "parameters", ma["parameters"], mb["parameters"])
        add_diff(differences, label, "raised", ma["raised"], mb["raised"])
        # Set only, not counts: this comparison treats "which call
        # sites exist" as the behavior-preservation signal, not how
        # many times each one fired.
        add_diff(differences, label, "callers", (ma["callers"] || {}).keys.sort, (mb["callers"] || {}).keys.sort)
        compare_bucket("#{label}.returns", ma["returns"], mb["returns"], differences)
        compare_params(label, ma["params"] || {}, mb["params"] || {}, differences)
      end

      def compare_params(label, params_a, params_b, differences)
        (params_a.keys | params_b.keys).each do |name|
          compare_bucket("#{label} param #{name}", params_a[name], params_b[name], differences)
        end
      end

      def compare_bucket(prefix, bucket_a, bucket_b, differences)
        bucket_a ||= {}
        bucket_b ||= {}
        add_diff(differences, prefix, "classes", bucket_a["classes"], bucket_b["classes"])
        add_diff(differences, prefix, "nil_count", bucket_a["nil_count"], bucket_b["nil_count"])
        compare_samples(prefix, bucket_a["samples"] || [], bucket_b["samples"] || [], differences)
      end

      def compare_samples(prefix, samples_a, samples_b, differences)
        normalized_a = normalize_samples(samples_a)
        normalized_b = normalize_samples(samples_b)
        return if normalized_a == normalized_b

        differences << "#{prefix}.samples changed (after normalizing object addresses): " \
                        "a=#{normalized_a.inspect} b=#{normalized_b.inspect}"
      end

      def normalize_samples(samples)
        samples.map do |sample|
          next sample unless sample.is_a?(Hash) && sample["value"].is_a?(String)

          sample.merge("value" => sample["value"].gsub(HEX_ADDRESS, "0x…"))
        end
      end

      def add_diff(differences, label, field, value_a, value_b)
        return if value_a == value_b

        differences << "#{label}.#{field} changed: a=#{value_a.inspect} b=#{value_b.inspect}"
      end
      private_class_method :compare_methods, :compare_method, :compare_params, :compare_bucket,
                            :compare_samples, :normalize_samples, :add_diff
    end
  end
end
