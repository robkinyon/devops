require 'devops/dns/record'

class DevOps
  class DNS
    class Zone
      # Taken from http://stackoverflow.com/a/11788082/1732954
      def symbolize(obj)
          return obj.inject({}){|memo,(k,v)| memo[k.to_sym] =  symbolize(v); memo} if obj.is_a? Hash
          return obj.inject([]){|memo,v    | memo           << symbolize(v); memo} if obj.is_a? Array
          return obj
      end

      attr_reader :client, :id, :default_ttl, :zone_name, :parent
      def initialize(parent, data, default_ttl=600)
        @parent = parent
        @client = parent.client
        @id = data.id
        @zone_name = data.name.gsub(/\.$/, '')
        @default_ttl = default_ttl
      end

      def records
        load_records unless @records
        @records
      end

      def record_for(name, type=nil)
        unless name.match(/#{zone_name}$/)
          name += '.' + zone_name
        end

        return unless records.has_key?(name)
        if type
          return records[name][type]
        end

        types = records[name].keys
        if types.length > 1
          raise DevOps::Error, "More than one type for #{name}: (#{types.sort.join(',')})"
        end
        return records[name][types.first]
      end

      def types_for(name)
        return unless records.has_key?(name)
        return records[name].keys
      end

      def ensure_record(record)
        record = symbolize(record)

        unless record.has_key?(:name) || record[:mail]
          raise DevOps::Error, "ensure_record requires a :name or mail:true"
        end

        # TODO: Verify we don't have both :value and :values

        if record.has_key? :value
          record[:values] = [
            { value: record.delete(:value) },
          ]
        end

        # TODO: Verify that :values is an Array[{value: String}]

        unless record.has_key? :values
          raise DevOps::Error, "ensure_record requires a :value or :values"
        end

        # TODO: Verify all the [:values][][:values] are the same type
        # TODO: Verify all of or none of the values have weights
        #   * All weights must be /^\d+$/
        #   * If no weights, then only one value
        record[:values].each do |item|
          zone = zone_of(item[:value])
          if zone && zone != zone_name
            other_zone = parent.zone_for(zone)
            if other_zone
              target = other_zone.record_for(item[:value], 'A') ||
                       other_zone.record_for(item[:value], 'CNAME') ||
                       other_zone.record_for(item[:value], 'ALIAS')
            end
          else
            target = record_for(item[:value], 'A') ||
                     record_for(item[:value], 'CNAME') ||
                     record_for(item[:value], 'ALIAS')
          end
          if target
            record[:type] = 'ALIAS'
            item[:target] = target
          else
            case item[:value]
            # A numeric IP address is a 'A' record
            # TODO: Verify the IP record is legal (1-255)
            when /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/
              record[:type] = 'A'
            else
              record[:type] = 'CNAME'
            end
          end
        end

        if record[:mail]
          record[:type] = 'MX'
          record[:name] ||= zone_name
          priority = 5
          record[:values].each do |item|
            item[:value] = [priority, item[:value]].join(' ')
            priority += 5
          end
        end

        # The AWS API requires fully-qualified names
        if record[:name] == '@'
          record[:name] = zone_name
        elsif !record[:name].match(/#{zone_name}$/)
          record[:name] += '.' + zone_name
        end

        if record_for(record[:name], record[:type])
          record[:action] = 'UPSERT'
        else
          record[:action] = 'CREATE'
        end

        issue_change_record(record)
      end

      private

      # FIXME: Get a proper DNS parsing tool
      def zone_of(proto)
        (_, match) = *proto.match(/([\w\d]+\.[\w\d]+)\.?$/)
        if match && !match.match(/^\d+\.\d+$/)
          match = match + '.' unless match[-1] == '.'
          return match
        end
        return
      end

      def issue_change_record(record)
        begin
          if record[:type] == 'ALIAS'
            changes = record[:values].map {|item|
              change = {
                action: record[:action],
                resource_record_set: {
                  name: record[:name],
                  type: item[:target].type,
                  alias_target: {
                    hosted_zone_id: item[:target].parent.id,
                    dns_name: item[:target].name,
                    evaluate_target_health: false,
                  },
                },
              }
              if item[:weight]
                change[:resource_record_set].merge!(
                  weight: item[:weight],
                  set_identifier: [record[:name], item[:target].name].join('-'),
                )
              end

              change
            }
          else
            # Mail records have multiple values, but one change record
            if record[:mail]
              changes = [
                {
                  action: record[:action],
                  resource_record_set: {
                    name: record[:name],
                    type: record[:type],
                    ttl: record[:ttl] || default_ttl,
                    resource_records: record[:values],
                  },
                },
              ]
            # Non-mail records have one change record per value
            else
              changes = record[:values].map {|item|
                change = {
                  action: record[:action],
                  resource_record_set: {
                    name: record[:name],
                    type: record[:type],
                    ttl: record[:ttl] || default_ttl,
                    resource_records: [{ value: item[:value] }],
                  },
                }
                if item[:weight]
                  change[:resource_record_set].merge!(
                    weight: item[:weight],
                    set_identifier: [record[:name], item[:value]].join('-'),
                  )
                end

                change
              }
            end
          end

          client.change_resource_record_sets(
            hosted_zone_id: id,
            change_batch: { changes: changes },
          )

          # TODO: Ensure the record is INSYNC
        rescue Aws::Route53::Errors::ServiceError => e
          #puts e
          raise DevOps::Error
        end
      end

      def load_records
        records = []
        begin
          rv = client.list_resource_record_sets(
            hosted_zone_id: id,
          )
          records.concat rv.resource_record_sets
          while rv.is_truncated
            rv = client.list_resource_record_sets(
              hosted_zone_id: id,
              start_record_name: rv.next_record_name,
              start_record_type: rv.next_record_type,
            )
            records.concat rv.resource_record_sets
          end
        rescue Aws::Route53::Errors::ServiceError => e
          #puts e
          raise DevOps::Error
        end

        @records = {}
        records.each do |record|
          name = record.name.gsub(/\.$/, '')
          type = record.alias_target ? 'ALIAS' : record.type

          @records[name] ||= {}
          #if @records[name][type]
          #  @records[name][type].add_record(record)
          #else
            @records[name][type] = DevOps::DNS::Record.new(self, record)
          #end
        end
      end
    end
  end
end
