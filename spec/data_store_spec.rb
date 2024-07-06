# frozen_string_literal:true

module ExcADG
  describe DataStore do
    subject(:dvertices) { Array.new(5) { double Vertex } }
    subject(:dother_vertex) { double Vertex }
    subject(:vstate_data_list) {
      Array.new(dvertices.size) { |i|
        VStateData::Full.new name: "me#{i}", vertex: dvertices[i], state: :ignored, data: :none
      }
    }
    subject(:vstate_data_0_named) { VStateData::Key.new name: vstate_data_list.first.name }
    subject(:vstate_data_0_vertice) { VStateData::Key.new vertex: dvertices.first }
    subject(:store) { DataStore.new }

    before {
      allow(Vertex).to receive(:===).and_return false
      dvertices.each { |dv|
        allow(dv).to receive(:is_a?).with(Array).and_return false
        allow(dv).to receive(:is_a?).with(Vertex).and_return true
        allow(Vertex).to receive(:===).with(dv).and_return true
      }

      subject << vstate_data_list[0]
      subject << vstate_data_list[1]
      subject << vstate_data_list[2]
    }

    it 'stores elements and returns by full key' do
      expect(store[vstate_data_list[2].to_key]).to eq vstate_data_list[2]
    end

    it 'does not have other elements' do
      expect(store[vstate_data_list[3].to_key]).to eq nil
    end

    it 'does not allow adding random data' do
      expect { store << :some }.to raise_error StandardError
    end

    it 'returns elements by name' do
      expect(store[vstate_data_0_named]).to eq vstate_data_list.first
    end

    it 'returns elements by vertex' do
      expect(store[vstate_data_0_vertice]).to eq vstate_data_list.first
    end

    it 'returns elements by plain vertex' do
      expect(store[dvertices.first]).to eq vstate_data_list.first
    end

    it 'returns elements by plain name' do
      expect(store[vstate_data_list.first.name]).to eq vstate_data_list.first
    end

    it 'maintains size' do
      expect(store.size).to eq 3
      store << vstate_data_list.last
      expect(store.size).to eq 4
      store << vstate_data_list.last
      expect(store.size).to eq 4
    end

    it 'returns uniq values' do
      expect(store.to_a.size).to eq store.size
    end

    it 'rejects renames' do
      dup_with_other_name = VStateData::Full.new name: 'other name', vertex: dvertices.first, state: :ignored, data: :none
      expect { store << dup_with_other_name }.to raise_error DataStore::DataSkew
    end

    it 'rejects vertex re-assignment' do
      dup_with_other_vertex = VStateData::Full.new name: vstate_data_list.first.name, vertex: dvertices.last, state: :ignored, data: :none
      expect { store << dup_with_other_vertex }.to raise_error DataStore::DataSkew
    end
  end
end
