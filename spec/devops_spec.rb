describe DevOps do
  describe '#instantiate' do
    it "with default region" do
      expect(Aws.config).to receive(:update).
        with(region: 'us-east-1')

      devops = DevOps.new
    end

    it "with provided region" do
      expect(Aws.config).to receive(:update).
        with(region: 'us-west-2')

      devops = DevOps.new('us-west-2')
    end
  end

  describe '#dns' do
    it 'is cached' do
      devops = DevOps.new
      dns = devops.dns
      expect(dns).to be_an(DevOps::DNS)
      expect(dns).to be(devops.dns)
    end
  end
end
