require 'open_api/dsl/common_dsl'

module OpenApi
  module DSL
    class ApiInfoObj < Hash
      include DSL::CommonDSL
      include DSL::Helpers

      attr_accessor :action_path, :param_skip, :param_use, :param_descs

      def initialize(action_path, skip: [ ], use: [ ])
        self.action_path = action_path
        self.param_skip  = skip
        self.param_use   = use
        self.param_descs = { }
      end

      def this_api_is_invalid! explain = ''
        self[:deprecated] = true
      end

      alias this_api_is_expired!     this_api_is_invalid!
      alias this_api_is_unused!      this_api_is_invalid!
      alias this_api_is_under_repair this_api_is_invalid!

      def desc desc, param_descs = { }
        self.param_descs = param_descs
        self[:description] = desc
      end

      def param param_type, name, type, required, schema_hash = { }
        return if param_skip.include?(name)
        return if param_use.present? && !param_use.include?(name)

        _t = nil
        schema_hash[:desc]  = _t if (_t = param_descs[name]).present?
        schema_hash[:desc!] = _t if (_t = param_descs["#{name}!".to_sym]).present?

        param_obj = ParamObj.new(name, param_type, type, required, schema_hash)
        # The definition of the same name parameter will be overwritten
        index = self[:parameters].map { |p| p.processed[:name] if p.is_a? ParamObj }.index name
        index.present? ? self[:parameters][index] = param_obj : self[:parameters] << param_obj
      end

      # Support this writing: (just like `form '', data: { }`)
      #   do_query by: {
      #     :search_type => { type: String  },
      #         :export! => { type: Boolean }
      #   }
      %i[header header! path path! query query! cookie cookie!].each do |param_type|
        define_method "do_#{param_type}" do |by:|
          by.each do |key, value|
            args = [ key.dup.to_s.delete('!'), value.delete(:type), value ]
            key.to_s['!'] ? send("#{param_type}!", *args) : send(param_type, *args)
          end
        end unless param_type.to_s['!']
      end

      def _param_agent name, type, schema_hash = { }
        param "#{@param_type}".delete('!'), name, type, (@param_type['!'] ? :req : :opt), schema_hash
      end

      def param_ref component_key, *keys
        self[:parameters].concat([component_key].concat(keys).map { |key| RefObj.new(:parameter, key).process })
      end

      def request_body required, media_type, desc = '', schema_hash = { }
        self[:requestBody] = RequestBodyObj.new(required, media_type, desc, schema_hash).process
      end

      def _request_body_agent media_type, desc = '', schema_hash = { }
        request_body (@method_name['!'] ? :req : :opt), media_type, desc, schema_hash
      end

      def body_ref component_key
        self[:requestBody] = RefObj.new(:requestBody, component_key).process
      end

      def override_response code, type_hash
        _response = self[:responses].fetch(code)
        self[:responses][code] = _response.override(type_hash).process
      end

      def response_ref code_compkey_hash
        code_compkey_hash.each do |code, component_key|
          self[:responses][code] = RefObj.new(:response, component_key).process
        end
      end

      # TODO: 目前只能写一句 request body，包括 form 和 file， 需要同时支持一下扁平化
      def form desc = '', schema_hash = { }
        body :form, desc, schema_hash
      end
      def form! desc = '', schema_hash = { }
        body! :form, desc, schema_hash
      end
      def file media_type, desc = '', schema_hash = { type: File }
        body media_type, desc, schema_hash
      end
      def file! media_type, desc = '', schema_hash = { type: File }
        body! media_type, desc, schema_hash
      end

      def security scheme_name, requirements = [ ]
        self[:security] << { scheme_name => requirements }
      end

      def server url, desc
        self[:servers] << { url: url, description: desc }
      end


      def _process_objs
        self[:parameters]&.each_with_index do |p, index|
          self[:parameters][index] = p.process if p.is_a?(ParamObj)
        end

        self[:responses]&.each do |code, obj|
          self[:responses][code] = obj.process if obj.is_a?(ResponseObj)
        end
      end
    end # ----------------------------------------- end of ApiInfoObj
  end
end
