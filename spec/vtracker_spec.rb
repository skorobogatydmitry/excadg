# frozen_string_literal: true

module ExcADG
  describe VTracker do
    subject(:dvmain) { double Vertex }
    subject(:dvmain_data) { double VStateData::Full }
    subject(:dvdep) { double Vertex }
    subject(:dvdep_data) { double VStateData::Full }
    subject(:dbroker_cls) { class_double(Broker).as_stubbed_const(transfer_nested_constants: true) }
    subject(:dbroker) { double Broker }
    subject(:ddata_store) { double DataStore }
    subject(:vtracker) { VTracker.new }

    before {
      allow(dvmain).to receive(:is_a?).with(Vertex).and_return true
      allow(dvdep).to receive(:is_a?).with(Vertex).and_return true
      allow(dvmain).to receive(:is_a?).with(Array).and_return false
      allow(dvdep).to receive(:is_a?).with(Array).and_return false

      allow(dbroker_cls).to receive(:instance).and_return dbroker
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

      expect(vtracker.graph.vertices).to eq [dvmain]
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

    context 'for root cause detection' do
      subject(:dv1) { double Vertex }
      subject(:dv2) { double Vertex }
      subject(:dv3) { double Vertex }
      subject(:dv4) { double Vertex }
      subject(:dv2data) { double VStateData }
      subject(:dv3data) { double VStateData }
      subject(:dv4data) { double VStateData }

      before {
        [dv1, dv2, dv3, dv4].each { |v|
          allow(v).to receive(:is_a?).with(Vertex).and_return true
          allow(v).to receive(:is_a?).with(Array).and_return false
        }
        allow(ddata_store).to receive(:[]).with(dv2).and_return dv2data
        allow(ddata_store).to receive(:[]).with(dv3).and_return dv3data
        allow(ddata_store).to receive(:[]).with(dv4).and_return dv4data
        allow(dv2data).to receive(:vertex).and_return dv2
        allow(dv3data).to receive(:vertex).and_return dv3
        allow(dv4data).to receive(:vertex).and_return dv4
      }

      it 'finds none if all passed' do
        [dv1, dv2, dv3, dv4].each { |v|
          expect(v).to receive(:state).and_return :some
          vtracker.track v
        }

        expect(vtracker.root_cause).to eq []
      end

      it 'finds the one failed' do
        expect(dv1).to receive(:state).and_return :some
        expect(dv2data).to receive(:state).and_return :some
        expect(dv3).to receive(:state).and_return :failed
        expect(dv3data).to receive(:state).and_return :failed
        expect(dv4).to receive(:state).and_return :some
        expect(dv4data).to receive(:state).and_return :some

        vtracker.track dv1, [dv2, dv3]
        vtracker.track dv3, [dv4]
        expect(vtracker.root_cause).to eq [dv3]
      end

      it 'finds several failed' do
        expect(dv1).to receive(:state).and_return :some
        expect(dv2data).to receive(:state).and_return :failed
        expect(dv3).to receive(:state).and_return :failed
        expect(dv3data).to receive(:state).and_return :failed
        expect(dv4data).to receive(:state).and_return :failed

        vtracker.track dv1, [dv2, dv3]
        vtracker.track dv3, [dv4]
      end
    end
  end
end
