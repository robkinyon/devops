require 'devops/dns/record'

class DevOps
  class DNS
    class Zone
      attr_reader :client, :id, :default_ttl
      def initialize(client, data)
        @client = client
        @id = data.id
        @default_ttl = 600
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
        unless record.has_key?('type')
          raise DevOps::Error, "ensure_record requires a 'type'"
        end

        #case record['type']
        #when 'MX'
        #  if !record['values']
        #    raise DevOps::Error, 'MX requires values OR value and optional priority'
        #  end
        #end
        create_record(record)
      end

      private

      def create_record(record)
        begin
          client.change_resource_record_sets(
            hosted_zone_id: id,
            change_batch: {
              changes: [
                {
                  name: record['name'],
                  type: record['type'],
                  # ttl doesn't work with ALIAS records
                  ttl: record['ttl'] || default_ttl,
                  resource_records: [
                    { value: record['value'] },
                  ],
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
          @records[record.name] ||= {}
          @records[record.name][record.type] = DevOps::DNS::Record.new(record)
        end
      end
    end
  end
end
