require 'active_support/ordered_options'

module ZeroRails
  module OpenApi
    module DSL
      def self.included(base)
        base.extend ClassMethods
      end

      module ClassMethods
        def controller_description desc = '', external_doc_url = ''
          @api_infos ||= { }
          # current `tag`, this means that tags is currently divided by controllers.
          @ctrl_infos = { name: controller_path.camelize }
          @ctrl_infos[:description] = desc if desc.present?
          @ctrl_infos[:externalDocs] = { description: 'ref', url: external_doc_url } if external_doc_url.present?
        end
        alias_method :c_desc, :controller_description

        def open_api method, summary = '', &block
          # select the routing info corresponding to the current method from the routing list.
          routes_info = ctrl_routes_list.select { |api| api[:ctrl_action].split('#').last.match? /^#{method}$/ }.first
          puts "[zero-rails_openapi] Routing mapping failed: #{controller_path}##{method}" or return if routes_info.nil?

          # structural { path: { http_method:{ } } }, refer to OpenAPI Spec.
          # it will be merged into :paths
          @api_infos[routes_info[:path]] ||= { }
          crt_api_info = @api_infos[routes_info[:path]][routes_info[:http_verb].downcase] = ApiInfoObj.new
          crt_api_info.summary = summary if summary.present?
          crt_api_info.operationId = method
          crt_api_info.tags = [controller_name.capitalize]

          crt_api_info.instance_eval &block
        end

        def ctrl_routes_list
          @routes_list ||= Generator.generate_routes_list
          @routes_list[controller_path]
        end
      end


      class ApiInfoObj < ActiveSupport::OrderedOptions
        def this_api_is_invalid! explain = ''
          self[:deprecated] = true
        end
        alias_method :this_api_is_expired!,           :this_api_is_invalid!
        alias_method :this_api_is_unused!,            :this_api_is_invalid!
        alias_method :this_api_is_under_maintenance!, :this_api_is_invalid!

        def desc desc
          self[:description] = desc
        end

        HASH_MAPPING = {
            _values:      [:values],
            _length:      [:length, :lth],
            _value:       [:value],
            _is:          [:is, :is_a],
            _regexp:      [:regexp, :reg],
            _default:     [:default, :dft],
            _swg_default: [:swg_default, :dft],
            _description: [:description, :desc, :d]
        } # TODO: Refactoring
        def param param_type, name, type, required, hash = { }
          processed_hash = { }
          type = type.to_s.downcase

          hash.instance_eval do
            HASH_MAPPING.each do |method_name, aliases|
              define_singleton_method method_name do
                aliases.each do |alias_name|
                  hash[method_name] ||= hash[alias_name]
                end
                hash[method_name]
              end
            end
          end

          # convert Range to Array
          [:_values, :_length].each do |key|
            setting = hash.send(key)
            hash[key] = setting.to_a if setting.present? && setting.is_a?(Range)
          end

          # process values to generate enums
          values = hash.send(:_values) || hash.send(:_value)
          unless values.nil?
            processed_hash.merge!({ allowable_values: {
                values: values.is_a?(Array) ? values : [values],
                value_type: type
            } })
          end

          # identify whether `is` patterns matched by name, and generate automatically
          is = hash.send(:_is)
          %w[email phone].each do |pattern|
            (processed_hash[:is] = pattern) && break if name.to_s.match? Regexp.new(pattern)
          end if is.nil?
          processed_hash[:is] = is unless is.nil?
          processed_hash.delete :is if is.eql? :x or is.eql? :we

          processed_hash[:length] = hash.send(:_length) unless hash.send(:_length).nil?
          processed_hash[:value] = hash.send(:_default) unless hash.send(:_default).nil?
          processed_hash[:regexp] = hash.send(:_regexp) unless hash.send(:_regexp).nil?
          processed_hash[:defaultValue] = hash.send(:_swg_default) unless hash.send(:_swg_default).nil?

          self[:parameters] ||= [ ]
          self[:parameters] << {
              param_type: param_type,
              name: name,
              type: type,
              description: hash.send(:_description),
              required: required.eql?(:req) || required.eql?(:required)
          }.merge(processed_hash)
        end

        [:header,  :path,  :query,  :cookie,
         :header!, :path!, :query!, :cookie!].each do |param_type|
          define_method param_type do |name, type, hash = { }|
            param param_type, name, type, (param_type.to_s.match?(/!/) ? :req : :opt), hash
          end
        end

        def security

        end

        # [{ :url, :description }]
        def server url, desc
          self[:servers] ||= []
          self[:servers] << { url: url, description: desc }
        end

        def response

        end
      end
    end
  end
end