# frozen_string_literal: true

module ExcADG
  describe VStateData::Key do
    subject(:dvertex) { double Vertex }
    subject(:dother_vertex) { double Vertex }

    subject(:with_vertex) { VStateData::Key.new vertex: dvertex }
    subject(:with_name) { VStateData::Key.new name: :some }
    subject(:same_vertex) { VStateData::Key.new vertex: dvertex }
    subject(:same_name) { VStateData::Key.new name: :some }
    subject(:with_both) { VStateData::Key.new vertex: dvertex, name: :some }

    subject(:other_vertex) { VStateData::Key.new vertex: dother_vertex }
    subject(:other_name) { VStateData::Key.new name: :other }

    before {
      allow(dvertex).to receive(:is_a?).with(Array).and_return(false).at_least 1
      allow(dother_vertex).to receive(:is_a?).with(Array).and_return(false).at_least 1
      allow(dvertex).to receive(:is_a?).with(Vertex).and_return true
      allow(dother_vertex).to receive(:is_a?).with(Vertex).and_return true
    }

    it 'equal' do
      expect(with_vertex <=> same_vertex).to eq 0
      expect(same_vertex <=> with_vertex).to eq 0
      expect(with_name <=> same_name).to eq 0
      expect(same_name <=> with_name).to eq 0

      expect(with_vertex).to eq same_vertex
      expect(same_vertex).to eq with_vertex

      expect(with_name).to eq same_name
      expect(same_name).to eq with_name

      expect(with_both).to eq with_name
      expect(with_both).to eq with_vertex
      expect(with_name).to eq with_both
      expect(with_vertex).to eq with_both
    end

    it 'not equals' do
      expect(with_vertex <=> other_vertex).not_to eq 0
      expect(with_name <=> other_name).not_to eq 0
      expect(with_both <=> other_vertex).not_to eq 0
      expect(with_both <=> other_name).not_to eq 0
      expect(other_vertex <=> with_both).not_to eq 0
      expect(other_name <=> with_both).not_to eq 0
    end

    it 'fails to construct' do
      expect { VStateData::Key.new }.to raise_error StandardError
    end

    it 'not comparable' do
      expect(with_vertex).not_to eq with_name
      expect(with_name).not_to eq with_vertex
      expect(with_vertex <=> with_name).to be nil
      expect(with_name <=> with_vertex).to be nil
      expect(with_name <=> :some).to be nil
    end

    it 'asserts for vertex type' do
      dvertex = double Vertex
      expect { VStateData::Key.new vertex: dvertex }.to raise_error StandardError
      expect(dvertex).to receive(:is_a?).with(Array).and_return(false).exactly 2
      expect(dvertex).to receive(:is_a?).with(Vertex).and_return true
      VStateData::Key.new vertex: dvertex
    end
  end

  describe VStateData::Full do
    subject(:dvertex) { double Vertex }
    subject { VStateData::Full.new name: :some, data: :dummy, state: :unknown, vertex: dvertex }

    before {
      allow(dvertex).to receive(:is_a?).with(Array).and_return(false).at_least 1
      allow(dvertex).to receive(:is_a?).with(Vertex).and_return true
    }

    it 'has all methods for states' do
      StateMachine::GRAPH.vertices.each { |state|
        method_name = "#{state}?".to_sym
        expect(subject).to respond_to method_name
        expect(subject.send(method_name)).to eq false
      }

      expect(subject).not_to respond_to :unknown?
      expect { subject.unknown? }.to raise_error NoMethodError
      another = VStateData::Full.new name: :some, data: :dummy, state: :new, vertex: dvertex
      expect(another.new?).to be true
    end

    it 'fills state and data' do
      expect(subject.state).to eq :unknown
      expect(subject.data).to eq :dummy
    end

    it 'fills current vertex from ractor' do
      expect(subject.vertex).to eq dvertex
      ErrorCatcher.new { VStateData::Full.new name: :some, data: :dummy, state: :unknown }.catch { |exc|
        expect(exc).to be_a StandardError
        expect(exc.message).to end_with 'not of classes [ExcADG::Vertex]'
      }
    end

    it 'supports converting to key' do
      key = subject.to_key
      expect(key).to eq subject
      expect(subject).to eq key
    end
  end
end
