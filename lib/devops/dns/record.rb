class DevOps
  class DNS
    class Record
      attr_reader :name, :type, :records
      def initialize(record)
        @name = record.name
        @type = record.type
        @records = []

        add_record(record)
      end

      def add_record(record)
        unless record.name == name && record.type == type
          raise DevOps::Error
        end
        @records.push record
      end
    end
  end
end
