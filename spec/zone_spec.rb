describe DevOps::DNS::Zone do
  let(:client) { instance_double('Aws::Route53::Client') }
  let(:zone) {
    DevOps::DNS::Zone.new(
      client,
      Aws::Route53::Types::HostedZone.new(id: 'id', name: 'foo.test.'),
    )
  }

  describe '#records' do
    it "can load zero records" do
      expect(client).to receive(:list_resource_record_sets).
        with(hosted_zone_id: 'id').
        and_return(
          Aws::Route53::Types::ListResourceRecordSetsResponse.new(
            resource_record_sets: [],
            is_truncated: false,
          )
        )
      expect(zone.records).to eq({})
      expect(zone.record_for('foo.test')).to eq(nil)
      expect(zone.record_for('foo.test', 'CNAME')).to eq(nil)
    end

    it "can load one record" do
      expect(client).to receive(:list_resource_record_sets).
        with(hosted_zone_id: 'id').
        and_return(
          Aws::Route53::Types::ListResourceRecordSetsResponse.new(
            resource_record_sets: [
              Aws::Route53::Types::ResourceRecordSet.new(
                name: 'foo.test',
                type: 'CNAME',
              ),
            ],
            is_truncated: false,
          )
        )
      expect(zone.records.keys).to match_array(['foo.test'])
      expect(zone.record_for('foo.test')).to be_an(DevOps::DNS::Record)
      expect(zone.record_for('foo.test', 'CNAME')).to be_an(DevOps::DNS::Record)
      expect(zone.record_for('foo.test')).to eq(zone.record_for('foo.test', 'CNAME'))
      expect(zone.types_for('foo.test')).to match_array(['CNAME'])
    end

    it "can load two records for the same name (with pagination)" do
      expect(client).to receive(:list_resource_record_sets).
        #with(hosted_zone_id: 'id').
        and_return(
          Aws::Route53::Types::ListResourceRecordSetsResponse.new(
            resource_record_sets: [
              Aws::Route53::Types::ResourceRecordSet.new(
                name: 'foo.test',
                type: 'CNAME',
              ),
            ],
            is_truncated: true,
            next_record_name: 'record',
            next_record_type: 'record',
          ),
          Aws::Route53::Types::ListResourceRecordSetsResponse.new(
            resource_record_sets: [
              Aws::Route53::Types::ResourceRecordSet.new(
                name: 'foo.test',
                type: 'A',
              ),
            ],
            is_truncated: false,
          )
        )
      expect(zone.records.keys).to match_array(['foo.test'])

      # We have too many records to return just one
      expect { zone.record_for('foo.test') }.to raise_error(
        DevOps::Error, /More than one type/
      )
      expect(zone.record_for('foo.test', 'CNAME')).to be_an(DevOps::DNS::Record)
      expect(zone.types_for('foo.test')).to match_array(['A', 'CNAME'])
    end

    it 'handles errors thrown' do
      expect(client).to receive(:list_resource_record_sets).
        and_raise(Aws::Route53::Errors::ServiceError.new(:context, 'message'))

      expect{ zone.records }.to raise_error(DevOps::Error)
    end
  end
end
