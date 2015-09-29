class DevOps
  class DNS
    class Record
      attr_reader :name, :type
      def initialize(record)
        @name = record.name
        @type = record.type
      end
    end
  end
end
