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
                name: 'foo.test.',
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
                name: 'foo.test.',
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
                name: 'foo.test.',
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

  # These tests are going to verify that ensure_record properly transforms what
  # it receives into calls to issue_change_record.
  describe '#ensure_record' do
    describe 'rejects' do
      it 'a record without a type' do
        expect {
          zone.ensure_record({})
        }.to raise_error(
          DevOps::Error, "ensure_record requires a 'type'"
        )
      end
    end

    describe 'type=MX' do
      it 'rejects a record without values' do
        expect {
          zone.ensure_record(
            'type' => 'MX',
            'name' => 'foo.test',
          )
        }.to raise_error(
          DevOps::Error, 'MX requires values to be set'
        )
      end

      it 'rejects a record without priority' do
        expect {
          zone.ensure_record(
            'type' => 'MX',
            'name' => 'foo.test',
            'values' => [ {} ],
          )
        }.to raise_error(
          DevOps::Error, 'Missing priority in MX record'
        )
      end

      it 'rejects a record without value' do
        expect {
          zone.ensure_record(
            'type' => 'MX',
            'name' => 'foo.test',
            'values' => [ { 'priority' => 5 } ],
          )
        }.to raise_error(
          DevOps::Error, 'Missing value in MX record'
        )
      end

      it 'creates a record with one value' do
        expect(client).to receive(:list_resource_record_sets).
          with(hosted_zone_id: 'id').
          and_return(
            Aws::Route53::Types::ListResourceRecordSetsResponse.new(
              resource_record_sets: [],
              is_truncated: false,
            )
          )
        expect(zone).to receive(:issue_change_record).
          with({
            'action' => 'CREATE',
            'type'   => 'MX',
            'name'   => 'foo.test',
            'records' => [
              { value: '5 mail.route.net' },
            ],
          })

        zone.ensure_record(
          'type'   => 'MX',
          'name'   => 'foo.test',
          'values' => [
            { 'priority' => 5, 'value' => 'mail.route.net' },
          ],
        )
      end

      it 'defaults the name to the zone name' do
        expect(client).to receive(:list_resource_record_sets).
          with(hosted_zone_id: 'id').
          and_return(
            Aws::Route53::Types::ListResourceRecordSetsResponse.new(
              resource_record_sets: [],
              is_truncated: false,
            )
          )
        expect(zone).to receive(:issue_change_record).
          with({
            'action' => 'CREATE',
            'type'   => 'MX',
            'name'   => 'foo.test',
            'records' => [
              { value: '5 mail.route.net' },
            ],
          })

        zone.ensure_record(
          'type'   => 'MX',
          'values' => [
            { 'priority' => 5, 'value' => 'mail.route.net' },
          ],
        )
      end
    end

    describe 'type=A' do
      it 'rejects a record without a name' do
        expect {
          zone.ensure_record({'type' => 'A'})
        }.to raise_error(
          DevOps::Error, "ensure_record requires a 'name'"
        )
      end

      it 'creates a record with one value' do
        expect(client).to receive(:list_resource_record_sets).
          with(hosted_zone_id: 'id').
          and_return(
            Aws::Route53::Types::ListResourceRecordSetsResponse.new(
              resource_record_sets: [],
              is_truncated: false,
            )
          )
        expect(zone).to receive(:issue_change_record).
          with({
            'action' => 'CREATE',
            'name'   => 'www.foo.test',
            'value'  => '1.2.3.4',
            'type'   => 'A',
          })

        zone.ensure_record(
          'name'  => 'www.foo.test',
          'value' => '1.2.3.4',
          'type'  => 'A',
        )
      end

      it 'updates a record with one value' do
        expect(client).to receive(:list_resource_record_sets).
          with(hosted_zone_id: 'id').
          and_return(
            Aws::Route53::Types::ListResourceRecordSetsResponse.new(
              resource_record_sets: [
                Aws::Route53::Types::ResourceRecordSet.new(
                  name: 'www.foo.test.',
                  type: 'A',
                ),
              ],
              is_truncated: false,
            )
          )
        expect(zone).to receive(:issue_change_record).
          with({
            'action' => 'UPSERT',
            'name'   => 'www.foo.test',
            'value'  => '1.2.3.4',
            'type'   => 'A',
          })

        zone.ensure_record(
          'name'  => 'www.foo.test',
          'value' => '1.2.3.4',
          'type'  => 'A',
        )
      end

      it 'creates a record with one value, no type passed' do
        expect(client).to receive(:list_resource_record_sets).
          with(hosted_zone_id: 'id').
          and_return(
            Aws::Route53::Types::ListResourceRecordSetsResponse.new(
              resource_record_sets: [],
              is_truncated: false,
            )
          )
        expect(zone).to receive(:issue_change_record).
          with({
            'action' => 'CREATE',
            'name'   => 'www.foo.test',
            'value'  => '1.2.3.4',
            'type'   => 'A',
          })

        zone.ensure_record(
          'name'  => 'www.foo.test',
          'value' => '1.2.3.4',
        )
      end
    end

    describe 'type=CNAME' do
      it 'rejects a record without a name' do
        expect {
          zone.ensure_record({'type' => 'CNAME'})
        }.to raise_error(
          DevOps::Error, "ensure_record requires a 'name'"
        )
      end

      it 'creates a record with one value' do
        expect(client).to receive(:list_resource_record_sets).
          with(hosted_zone_id: 'id').
          and_return(
            Aws::Route53::Types::ListResourceRecordSetsResponse.new(
              resource_record_sets: [],
              is_truncated: false,
            )
          )
        expect(zone).to receive(:issue_change_record).
          with({
            'action' => 'CREATE',
            'name'   => 'www.foo.test',
            'value'  => 'www2.foo.test',
            'type'   => 'CNAME',
          })

        zone.ensure_record(
          'name'  => 'www.foo.test',
          'value' => 'www2.foo.test',
          'type'  => 'CNAME',
        )
      end

      it 'creates a record with one value, no type passed' do
        expect(client).to receive(:list_resource_record_sets).
          with(hosted_zone_id: 'id').
          and_return(
            Aws::Route53::Types::ListResourceRecordSetsResponse.new(
              resource_record_sets: [],
              is_truncated: false,
            )
          )
        expect(zone).to receive(:issue_change_record).
          with({
            'action' => 'CREATE',
            'name'   => 'www.foo.test',
            'value'  => 'www2.foo.test',
            'type'   => 'CNAME',
          })

        zone.ensure_record(
          'name'  => 'www.foo.test',
          'value' => 'www2.foo.test',
        )
      end

      it 'defaults the name to the zone name' do
        expect(client).to receive(:list_resource_record_sets).
          with(hosted_zone_id: 'id').
          and_return(
            Aws::Route53::Types::ListResourceRecordSetsResponse.new(
              resource_record_sets: [],
              is_truncated: false,
            )
          )
        expect(zone).to receive(:issue_change_record).
          with({
            'action' => 'CREATE',
            'name'   => 'www.foo.test',
            'value'  => 'www2.foo.test',
            'type'   => 'CNAME',
          })

        zone.ensure_record(
          'name'  => 'www',
          'value' => 'www2.foo.test',
          'type'  => 'CNAME',
        )
      end
    end

    it 'handles errors thrown' do
      expect(client).to receive(:list_resource_record_sets).
        with(hosted_zone_id: 'id').
        and_return(
          Aws::Route53::Types::ListResourceRecordSetsResponse.new(
            resource_record_sets: [],
            is_truncated: false,
          )
        )
      expect(client).to receive(:change_resource_record_sets).
        and_raise(Aws::Route53::Errors::ServiceError.new(:context, 'message'))

      expect{
        zone.ensure_record({
          'name' => 'www.foo.test',
          'type' => 'A',
          'value' => '1.2.3.4',
        })
      }.to raise_error(DevOps::Error)
    end
  end
end
