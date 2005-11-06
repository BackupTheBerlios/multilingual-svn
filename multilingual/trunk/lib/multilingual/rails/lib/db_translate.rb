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

        facets_string = "[" + facets.map {|facet| ":#{facet}"}.join(", ") + "]"
        class_eval <<-HERE

          class << self
            @@multilingual_facets = #{facets_string}

            def multilingual_facets
              @@multilingual_facets
            end

            def multilingual_facets_hash
              @@multilingual_facets_hash ||= multilingual_facets.inject({}) {|hash, facet|
                hash[facet.to_s] = true; hash
              }
            end            
            
            alias_method :untranslated_find, :find unless
              respond_to? :untranslated_find
            alias_method :old_find_by_sql, :find_by_sql unless
              respond_to? :old_find_by_sql
          end
          alias_method :multilingual_old_create_or_update, :create_or_update
        
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

      end

    end

    module TranslateObjectMethods # :nodoc: all
      private    

        def create_or_update
          multilingual_old_create_or_update
          update_translation
        end
        
        def update_translation
          language_id = Language.active_language.id
          base_language_id = Language.base_language.id
          base_language = (language_id == base_language_id)
          supported_langs = Language.supported_languages
          
          table_name = self.class.table_name
          self.class.multilingual_facets.each do |facet|
            text = send(facet)
            tr = Translation.find(:first, :conditions =>
              [ "table_name = ? AND item_id = ? AND facet = ? AND language_id = ?",
              table_name, id, facet.to_s, language_id ])
            if tr.nil?
              # create new record
              Translation.create(:table_name => table_name, 
                :item_id => id, :facet => facet.to_s, 
                :language_id => language_id,
                :text => text) if !text.nil? || base_language
            else 
              # update record
              if text.nil? && !base_language  # set back to base translation
                base_tr = Translation.find(:first, :conditions =>
                  [ "table_name = ? AND item_id = ? AND facet = ? AND language_id = ?",
                  table_name, id, facet.to_s, base_language_id ])
                tr.update_attributes(:text => base_tr.text, :untranslated => true) if 
                  !base_tr.nil?                
              else
                tr.update_attributes(:text => text, :untranslated => false)
              end
            end

            # if base translation changed, update all untranslated languages
            if base_language
              supported_langs.each do |lang|
                lang_id = lang.id
                tr = Translation.find(:first, :conditions =>
                  [ "table_name = ? AND item_id = ? AND facet = ? AND language_id = ?",
                  table_name, id, facet.to_s, lang_id ])
                if tr.nil?  # add new "untranslated" record which copies base translation
                  Translation.create(:table_name => table_name, 
                    :item_id => id, :facet => facet.to_s, 
                    :language_id => lang_id,
                    :text => text, :untranslated => true)
                elsif tr.untranslated?  # update to base translation
                  tr.update_attribute(:text, text)
                end                     # otherwise leave it alone -- has own translation
              end
            end
          end # end facets loop
        end

    end

    module TranslateClassMethods  # :nodoc: all
      
      def find(*args)
        options = args.last.is_a?(Hash) ? args.last : {}

        return untranslated_find(*args) if args.first != :all

        raise ":select option not allowed on translatable models" if options.has_key?(:select)
        options[:conditions] = fix_conditions(options[:conditions]) if options[:conditions]

        language_id = Language.active_language.id
        base_language_id = Language.base_language.id

        facets = multilingual_facets
        select_clause = "#{table_name}.* "
        joins_clause = options[:joins].nil? ? "" : options[:joins].dup
        joins_args = []

        facets.each do |facet| 
          facet = facet.to_s
          facet_alias = "t_#{facet}"
          select_clause << ", #{facet_alias}.text AS #{facet} "
          joins_clause  << " LEFT OUTER JOIN translations AS #{facet_alias} " +
            "ON #{facet_alias}.table_name = ? " +
            "AND #{table_name}.#{primary_key} = #{facet_alias}.item_id " +
            "AND #{facet_alias}.facet = ? AND #{facet_alias}.language_id = ?"
          joins_args << table_name << facet << language_id            
        end

        options[:select] = select_clause
        options[:readonly] = false

        sanitized_joins_clause = sanitize_sql( [ joins_clause, *joins_args ] )        
        options[:joins] = sanitized_joins_clause
        untranslated_find(:all, options)
      end

      private

        # properly scope conditions to table
        def fix_conditions(conditions)
          if conditions.kind_of? Array          
            is_array = true
            sql = conditions.shift
          else
            is_array = false
            sql = conditions
          end
          column_names.each do |column_name|
            sql.gsub!(/([^\.\w])(#{column_name})(\W)/, '\1' + table_name + '.\2\3')
          end
          if is_array
            [ sql ] + conditions
          else
            sql
          end
        end

    end
  end

end
