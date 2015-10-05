describe DevOps::DNS::Zone do
  let(:zone_id) { 'id' }
  let(:client) { instance_double('Aws::Route53::Client') }
  let(:zone) {
    DevOps::DNS::Zone.new(
      client,
      Aws::Route53::Types::HostedZone.new(id: zone_id, name: 'foo.test.'),
    )
  }

  def setup_zone(*rv)
    expect(client).to receive(:list_resource_record_sets).
      with(hosted_zone_id: zone_id).
      and_return(*rv)
  end

  def setup_paginated_zone(with_returns)
    with_returns.each do |with, returns|
      expect(client).to receive(:list_resource_record_sets).ordered.
        with(with.merge(hosted_zone_id: zone_id)).
        and_return(*returns)
    end
  end

  def records(records=[], overrides={})
    opts = {
      resource_record_sets: records,
      is_truncated: false,
    }.merge(overrides)

    Aws::Route53::Types::ListResourceRecordSetsResponse.new(opts)
  end

  def record(opts={})
    Aws::Route53::Types::ResourceRecordSet.new(opts)
  end

  def setup_empty_zone
    setup_zone( records() )
  end

  describe '#records' do
    it "can load zero records" do
      setup_empty_zone()
      expect(zone.records).to eq({})
      expect(zone.record_for('foo.test')).to eq(nil)
      expect(zone.record_for('foo.test', 'CNAME')).to eq(nil)
    end

    it "can load one record" do
      setup_zone(
        records([ record( name: 'foo.test.', type: 'CNAME') ])
      )
      expect(zone.records.keys).to match_array(['foo.test'])
      expect(zone.record_for('foo.test')).to be_an(DevOps::DNS::Record)
      expect(zone.record_for('foo.test', 'CNAME')).to be_an(DevOps::DNS::Record)
      expect(zone.record_for('foo.test')).to eq(zone.record_for('foo.test', 'CNAME'))
      expect(zone.types_for('foo.test')).to match_array(['CNAME'])
    end

    it "can load two records for the same name (with pagination)" do
      setup_paginated_zone(
        {} => [
          records(
            [ record(name: 'foo.test.', type: 'CNAME') ],
            is_truncated: true,
            next_record_name: 'record',
            next_record_type: 'record',
          ),
        ],
        { start_record_name: 'record', start_record_type: 'record' } => [
          records(
            [ record(name: 'foo.test.', type: 'A') ],
          ),
        ]
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
        setup_empty_zone()
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
        setup_empty_zone()
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
        setup_empty_zone()

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
        setup_zone(
          records(
            [ record(name: 'www.foo.test.', type: 'A') ],
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
        setup_empty_zone()

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
        setup_empty_zone()

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
        setup_empty_zone()

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

      it 'defaults the name suffix to the zone name' do
        setup_empty_zone()

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

      it 'treats @ as the zone name' do
        setup_empty_zone()

        expect(zone).to receive(:issue_change_record).
          with({
            'action' => 'CREATE',
            'name'   => 'foo.test',
            'value'  => 'www2.foo.test',
            'type'   => 'CNAME',
          })

        zone.ensure_record(
          'name'  => '@',
          'value' => 'www2.foo.test',
          'type'  => 'CNAME',
        )
      end
    end

    describe 'type=ALIAS' do
      it 'rejects a record without a name' do
        expect {
          zone.ensure_record({'type' => 'ALIAS'})
        }.to raise_error(
          DevOps::Error, "ensure_record requires a 'name'"
        )
      end

      it 'creates a record with one value' do
        setup_zone(
          records(
            [ record(name: 'www.foo.test.', type: 'A') ],
          )
        )

        # Get the target so .with() passes properly
        target = zone.record_for('www')

        expect(zone).to receive(:issue_change_record).
          with({
            'action' => 'CREATE',
            'name'   => 'www2.foo.test',
            'value'  => 'www',
            'target' => target,
            'type'   => 'ALIAS',
          })

        zone.ensure_record(
          'name'  => 'www2',
          'value' => 'www',
        )
      end

      it 'calls the client with the right values' do
        setup_zone(
          records(
            [ record(name: 'www.foo.test.', type: 'A') ]
          )
        )

        expect(client).to receive(:change_resource_record_sets).
          with(
            hosted_zone_id: zone.id,
            change_batch: {
              changes: [
                {
                  action: 'CREATE',
                  resource_record_set: {
                    name: 'www2.foo.test',
                    type: 'A',
                    alias_target: {
                      hosted_zone_id: zone.id,
                      dns_name: 'www.foo.test.',
                      evaluate_target_health: false,
                    },
                  },
                },
              ],
            },
          )

        zone.ensure_record(
          'name'  => 'www2',
          'value' => 'www',
        )
      end
    end

    xdescribe 'weighted records' do
      it 'creates a 2-record weighted set' do
        setup_empty_zone()

        # set_identifier
        expect(zone).to receive(:issue_change_record).
          with({
            'action' => 'CREATE',
            'name'   => 'www.foo.test',
            'value'  => 'www1.bar.test',
            'type'   => 'CNAME',
            'weight' => 3,
          }, {
            'action' => 'CREATE',
            'name'   => 'www.foo.test',
            'value'  => 'www2.bar.test',
            'type'   => 'CNAME',
            'weight' => 1,
          })

        zone.ensure_record(
          'name'  => 'www',
          'values' => [
            { 'value' => 'www1.bar.test', 'weight' => 3 },
            { 'value' => 'www2.bar.test', 'weight' => 1 },
          ],
        )
      end
    end

    it 'handles errors thrown' do
      setup_empty_zone()

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
