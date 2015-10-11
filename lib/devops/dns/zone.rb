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

      attr_reader :client, :id, :default_ttl, :zone_name
      def initialize(client, data, default_ttl=600)
        @client = client
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
        record[:values].each do |item|
          target = record_for(item[:value], 'A') ||
                   record_for(item[:value], 'CNAME')
          if target
            record[:type] = 'ALIAS'
            record[:target] = target
          else
            case item[:value]
            # A numeric IP address is a 'A' record
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

      def issue_change_record(record)
        begin
          if record[:type] == 'ALIAS'
            client.change_resource_record_sets(
              hosted_zone_id: id,
              change_batch: {
                changes: [
                  {
                    action: record[:action],
                    resource_record_set: {
                      name: record[:name],
                      type: record[:target].type,
                      alias_target: {
                        # Currently, only intra-zone ALIASes are supported.
                        hosted_zone_id: id,
                        dns_name: record[:target].name,
                        evaluate_target_health: false,
                      },
                    },
                  },
                ],
              },
            )
          else
            client.change_resource_record_sets(
              hosted_zone_id: id,
              change_batch: {
                changes: [
                  {
                    action: record[:action],
                    resource_record_set: {
                      name: record[:name],
                      type: record[:type],
                      # ttl doesn't work with ALIAS records
                      ttl: record[:ttl] || default_ttl,
                      resource_records: record[:values],
                    },
                  },
                ],
              },
            )
          end

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
            @records[name][type] = DevOps::DNS::Record.new(record)
          #end
        end
      end
    end
  end
end
