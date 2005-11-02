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
            alias_method :multilingual_old_find_by_sql, :find_by_sql unless
              respond_to? :multilingual_old_find_by_sql
          end

          include Multilingual::DbTranslate::TranslateObjectMethods
          extend  Multilingual::DbTranslate::TranslateClassMethods

          attr_accessor(*facets)
                
        HERE
        
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

        def segregate_facets(attributes)
          return if attributes.nil?
          self.class.multilingual_facets.each do |f|
            val = attributes.delete(f)
            send(f.to_s + '=', val) unless val.nil?
          end
        end      
    end

    module TranslateClassMethods  # :nodoc: all
      attr_accessor :multilingual_facets, :multilingual_facets_hash

      def facets_hash 
        self.multilingual_facets_hash ||= multilingual_facets.inject({}) do |hash, facet| 
          hash[facet.to_s] = true; hash
        end
      end          
      
      def find_by_sql(sql)

        # get results from old find
        results = multilingual_old_find_by_sql(sql)

        inject_translations!(results)

        # return items
        results
      end

      def inject_translations!(results)

        results = [ results ] if !results.kind_of? Array
        return if results.empty?
        trs = fetch_translations(results)

        # organize translations by item (hash of items containing arrays of facets)
        translated_items = Hash.new
        trs.each do |tr|
          item_id = tr.item_id
          arr = translated_items[item_id]
          arr ||= Array.new
          arr.push(tr)
          translated_items[item_id] = arr
        end

        # set facets in items
        missed_translations = {}
        active_lang_id = Language.active_language.id
        results.each do |item|
          arr = translated_items[item.id]
          arr && arr.each do |tr|
            facet = tr.facet
            rec_lang_id = tr.language_id
            
            if active_lang_id == rec_lang_id
              missed_translations[item] = false
              item.send( "#{facet}=".to_sym, tr.text )
            elsif item.send( facet.to_sym ).nil?
              missed_translations[item] = true
              item.send( "#{facet}=".to_sym, tr.text )
            else
              missed_translations[item] = true
            end            
          end
        end
        
        # log missed translations
        log_missed(missed_translations)

      end

      private
        def fetch_translations(results)
          active_language = Language.active_language
          raise "no active language" if active_language.nil?
          language_id = active_language.id
          base_language_id = Language.base_language.id

          item_ids = results.collect {|r| sanitize(r.id) }
          item_ids.uniq!

          conditions = "table_name = ? AND "
          if item_ids.size == 1
            conditions << "item_id = #{item_ids.first} AND "
          else 
            item_id_list = item_ids.join(',')
            conditions << "item_id IN (#{item_id_list}) AND "
          end
          conditions << " ( language_id = ? OR language_id = ? )"
          Translation.find(:all, :conditions => [ conditions, 
            table_name, language_id, base_language_id ])
        end

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
