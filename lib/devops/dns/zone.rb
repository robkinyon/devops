class DevOps
  class DNS
    class Zone
      attr_reader :client, :id
      def initialize(client, data)
        @client = client
        @id = data.id
      end
    end
  end
end
