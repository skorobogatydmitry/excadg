# frozen_string_literal: true

module ExcADG
  describe VTracker do
    subject(:dvmain) { double Vertex }
    subject(:dvmain_data) { double VStateData::Full }
    subject(:dvdep) { double Vertex }
    subject(:dvdep_data) { double VStateData::Full }
    subject(:dbroker) { class_double(Broker).as_stubbed_const(transfer_nested_constants: true) }
    subject(:ddata_store) { double DataStore }
    subject(:vtracker) { VTracker.new }

    before {
      allow(dvmain).to receive(:is_a?).with(Vertex).and_return true
      allow(dvdep).to receive(:is_a?).with(Vertex).and_return true
      allow(dvmain).to receive(:is_a?).with(Array).and_return false
      allow(dvdep).to receive(:is_a?).with(Array).and_return false

      allow(dbroker).to receive(:data_store).and_return ddata_store
      %i[one two three four].each { |ghost_dep|
        allow(ddata_store).to receive(:'[]').with(ghost_dep).and_return nil
      }

      allow(ddata_store).to receive(:'[]').with(dvmain).and_return dvmain_data
      allow(ddata_store).to receive(:'[]').with(dvdep).and_return dvdep_data

      allow(dvmain_data).to receive(:vertex).and_return dvmain
      allow(dvdep_data).to receive(:vertex).and_return dvdep
    }
    it 'tracks vertices' do
      allow(dvmain).to receive(:state).and_return :done
      allow(dvdep).to receive(:state).and_return :failed
      allow(dvmain_data).to receive(:state).and_return :done
      allow(dvdep_data).to receive(:state).and_return :failed

      vtracker.track dvmain, [:one, :two, dvdep]

      expect(vtracker.by_state.keys).to eq %i[done failed]
      expect(vtracker.by_state[:done]).to eq [dvmain]
      expect(vtracker.by_state[:failed]).to eq [dvdep]
      expect(vtracker.graph.vertices).to eq [dvmain, dvdep]

      vtracker.track dvdep, %i[two three four]
      expect(vtracker.by_state.keys).to eq %i[done failed]
      expect(vtracker.by_state[:done]).to eq [dvmain]
      expect(vtracker.by_state[:failed]).to eq [dvdep]

      expect(vtracker.graph.vertices).to eq [dvmain, dvdep]
    end
    it 'allows to track vertices without deps' do
      allow(dvmain).to receive(:state).and_return :done

      vtracker.track dvmain

      expect(vtracker.graph.vertices).to eq [dvmain]
    end
    it 'links hanging vertices if they appear as deps' do
      allow(dvmain).to receive(:state).and_return :new
      allow(dvdep).to receive(:state).and_return :done
      allow(dvdep_data).to receive(:state).and_return :done

      vtracker.track dvdep
      expect(vtracker.graph.vertices).to eq [dvdep]

      vtracker.track dvmain, [dvdep]

      expect(vtracker.graph.vertices).to eq [dvdep, dvmain]
      expect(vtracker.graph.adjacent_vertices(dvmain)).to eq [dvdep]
    end
    it 'ignores vertices without state' do
      allow(dvmain).to receive(:state).and_return nil
      allow(dvmain_data).to receive(:state).and_return nil

      vtracker.track dvmain, %i[one two]

      expect(vtracker.graph.vertices).to eq []
    end
    it 'returns dependencies if any' do
      allow(dvmain).to receive(:state).and_return :new
      allow(dvdep).to receive(:state).and_return :done
      allow(dvdep_data).to receive(:state).and_return :done

      vtracker.track dvmain, [dvdep]

      expect(vtracker.graph.vertices).to eq [dvmain, dvdep]
      expect(vtracker.graph.adjacent_vertices(dvmain)).to eq [dvdep]

      expect(vtracker.get_deps(dvmain)).to eq [dvdep]
      expect(vtracker.get_deps(dvdep)).to be_empty
    end
  end
end
