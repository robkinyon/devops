require 'devops/dns/record'

class DevOps
  class DNS
    class Zone
      attr_reader :client, :id, :default_ttl, :name
      def initialize(client, data, default_ttl=600)
        @client = client
        @id = data.id
        @name = data.name.gsub(/\.$/, '')
        @default_ttl = default_ttl
      end

      def records
        load_records unless @records
        @records
      end

      def record_for(name, type=nil)
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
        if record.has_key?('value')
          case record['value']
          # A numeric IP address is a 'A' record
          when /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/
            record['type'] ||= 'A'
          else
            record['type'] ||= 'CNAME'
          end
        end

        unless record.has_key?('type')
          raise DevOps::Error, "ensure_record requires a 'type'"
        end

        # Transform what we receive into what we expect.
        case record['type']
        when 'MX'
          if !record['values']
            raise DevOps::Error, 'MX requires values to be set'
          end

          # Default the name for MX records to the zone's name
          record['name'] ||= name

          record['records'] = record.delete('values').map {|item|
            ['priority', 'value'].each do |key|
              unless item.has_key?(key)
                raise DevOps::Error, "Missing #{key} in MX record"
              end
            end

            { value: item.values_at('priority', 'value').join(' ') }
          }
        else
          unless record.has_key?('name')
            raise DevOps::Error, "ensure_record requires a 'name'"
          end
          # The AWS API requires fully-qualified names
          unless record['name'].match(/#{name}$/)
            record['name'] += '.' + name
          end
        end

        # This doesn't handle weighted sets (yet)
        if record_for(record['name'], record['type'])
          record['action'] = 'UPSERT'
        else
          record['action'] = 'CREATE'
        end

        issue_change_record(record)
      end

      private

      def issue_change_record(record)
        record['records'] ||= [
          { value: record['value'] }
        ]

        begin
          client.change_resource_record_sets(
            hosted_zone_id: id,
            change_batch: {
              changes: [
                {
                  action: record['action'],
                  resource_record_set: {
                    name: record['name'],
                    type: record['type'],
                    # ttl doesn't work with ALIAS records
                    ttl: record['ttl'] || default_ttl,
                    resource_records: record['records'],
                  },
                },
              ],
            },
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
          @records[name] ||= {}
          @records[name][record.type] = DevOps::DNS::Record.new(record)
        end
      end
    end
  end
end
