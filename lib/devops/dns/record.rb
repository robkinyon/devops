class DevOps
  class DNS
    class Record
      attr_reader :name, :type, :records, :parent
      def initialize(parent, record)
        @parent = parent
        @name = record.name
        @type = record.type
        @records = []

        add_record(record)
      end

      def add_record(record)
        #unless record.name == name && record.type == type
        #  raise DevOps::Error
        #end
        @records.push record
      end
    end
  end
end
