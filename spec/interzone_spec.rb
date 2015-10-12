describe DevOps::DNS do
  let(:zone_id) { 'id for foo.test.' }
  let(:client) { instance_double('Aws::Route53::Client') }
  let(:dns) { DevOps::DNS.new(client) }

  describe '::Zone#ensure_record' do
    it 'creates an inter-zone value' do
      # This is the list of all zones
      setup_zone_list(
        zones([
          zone_for(id: 'id for foo.test.', name: 'foo.test.'),
          zone_for(id: 'id for bar.test.', name: 'bar.test.'),
        ])
      )

      # This is the target zone
      expect(client).to receive(:list_resource_record_sets).ordered.
        with(hosted_zone_id: 'id for bar.test.').
        and_return(
          records(
            [ record(name: 'bar.test.', type: 'A') ],
          )
        )

      # This is our zone
      setup_empty_zone()

      expect_alias_record(
        changes: [
          {
            action: 'CREATE',
            resource_record_set: {
              name: 'foo.test',
              type: 'A',
              alias_target: {
                hosted_zone_id: 'id for bar.test.',
                dns_name: 'bar.test.',
                evaluate_target_health: false,
              },
            },
          },
        ],
      )

      dns.zone_for('foo.test').ensure_record(
        name: '@',
        value: 'bar.test',
      )
    end
  end
end
