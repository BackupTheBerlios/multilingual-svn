module Multilingual # :nodoc:
  module DbTranslate  # :nodoc:

    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
=begin rdoc
          Specifies fields that can be translated. These fields are stored in a
          special translations tables, not in the model table.
          
          === Example:
          
          ==== In model:
            class Product < ActiveRecord::Base
              translates :name, :description
            end
          
          ==== In controller:
            Locale.set("en_US")
            product.name -> guitar
            
            Locale.set("es_ES")
            product.name -> guitarra
=end
      def translates(*facets)

        class_eval <<-HERE
          class << self
            alias_method :untranslated_find, :find unless
              respond_to? :untranslated_find
            alias_method :old_find_by_sql, :find_by_sql unless
              respond_to? :old_find_by_sql
          end
        
          include Multilingual::DbTranslate::TranslateObjectMethods
          extend  Multilingual::DbTranslate::TranslateClassMethods        

        HERE

        facets.each do |facet|
          class_eval <<-HERE
            def #{facet}
              read_attribute(:#{facet})
            end

            def #{facet}=(arg)
              write_attribute(:#{facet}, arg)
            end
          HERE
        end

        self.multilingual_facets = facets             
      end

    end

    module TranslateObjectMethods # :nodoc: all
      private    
        def update_translation
          language_id = Language.active_language.id

          table_name = self.class.table_name
          self.class.multilingual_facets.each do |facet|
            text = send(facet)
            next if text.nil? || text.empty?
            tr = Translation.find(:first, :conditions =>
              [ "table_name = ? AND item_id = ? AND facet = ? AND language_id = ?",
              table_name, id, facet.to_s, language_id ])
            if tr.nil?
              # create new record
              Translation.create(:table_name => table_name, 
                :item_id => id, :facet => facet.to_s, 
                :language_id => language_id,
                :text => text)
            else 
              # update record
              tr.update_attribute(:text, text)
            end
          end
        end

    end

    module TranslateClassMethods  # :nodoc: all
      attr_accessor :multilingual_facets, :multilingual_facets_hash
      
      def find(*args)
        options = args.last.is_a?(Hash) ? args.last : {}

        return untranslated_find(*args) if args.first != :all

        raise ":select option not allowed on translatable models" if options.has_key?(:select)

        language_id = Language.active_language.id
        base_language_id = Language.base_language.id

        facets = multilingual_facets
        select_clause = "#{table_name}.* "
        joins_clause = options[:joins] || ""
        active_joins_args = []
        base_joins_args   = []
        facets.each do |facet| 
          facet = facet.to_s
          facet_alias = "t_#{facet}"
          select_clause << ", #{facet_alias}.text AS #{facet} "
          joins_clause  << " LEFT OUTER JOIN translations AS #{facet_alias} " +
            "ON #{facet_alias}.table_name = ? " +
            "AND #{table_name}.#{primary_key} = #{facet_alias}.item_id " +
            "AND #{facet_alias}.facet = ? AND #{facet_alias}.language_id = ?"
          active_joins_args << table_name << facet << language_id            
          base_joins_args << table_name << facet << base_language_id            
        end

        options[:select] = select_clause
        options[:readonly] = false

        if base_language_id != language_id
          sanitized_joins_clause = sanitize_sql( [ joins_clause, *base_joins_args ] )
          options[:joins] = sanitized_joins_clause
          base_results = untranslated_find(:all, options)
          base_map = {}
          base_results.each do |result|
            base_map[result.id] ||= {}
            facets.each do |facet|
              base_map[result.id][facet] = result.send(facet)
            end
          end
          base_results = nil    # try to free up some memory
        end

        sanitized_joins_clause = sanitize_sql( [ joins_clause, *active_joins_args ] )
        options[:joins] = sanitized_joins_clause
        active_results = untranslated_find(:all, options)

        if base_language_id != language_id
          # substitute base facets where needed
          active_results.each do |result|
            facets.each do |facet|
              result.send("#{facet}=", base_map[result.id][facet]) if
                result.send(facet).nil?
            end          
          end
        end

        active_results
      end

=begin
      def find_by_sql(sql)
        p sanitize_sql(sql)
        results = connection.select_all(sanitize_sql(sql), "#{name} Load")
        p results
        results = old_find_by_sql(sql)
        p results
        results
      end
=end

      private

        def log_missed(missed_translations)
          missed_translations.each do |item, missed|
            next if !missed
            
            type = item.class.name
            id_num = item.id
            code = item.respond_to?(:label) ? item.label : nil
            msg = "#{type}::#{id_num}"
            msg << " (#{code})" if !code.nil?
            @@log_path ||= false            
            unless @@log_path
              if Locale.const_defined? :MLR_LOG_PATH
                @@log_path = MLR_LOG_PATH
              else
                @@log_path = DEFAULT_MLR_LOG_PATH
              end
            end
            
            @@log_format ||= false
            unless @@log_format
              if Locale.const_defined? :MLR_LOG_FORMAT
                @@log_format = MLR_LOG_FORMAT
              else
                @@log_format = DEFAULT_MLR_LOG_FORMAT
              end
            end
        
            FileUtils.mkdir_p File.dirname(@@log_path % [Locale.current])
            RAILS_DEFAULT_LOGGER.class.new(@@log_path % [Locale.current]).warn(
              @@log_format % ['content', Locale.current, msg, Time.now.strftime('%Y-%m-%d %H:%M:%S')]
            )
            
          end
        end
    end
  end

end
