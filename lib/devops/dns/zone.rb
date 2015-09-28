require 'devops/dns/record'

class DevOps
  class DNS
    class Zone
      attr_reader :client, :id
      def initialize(client, data)
        @client = client
        @id = data.id
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

      private
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
