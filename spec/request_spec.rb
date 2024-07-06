# frozen_string_literal: true

module ExcADG
  describe Request do
    it 'has self' do
      expect(subject.self).to eq Ractor.current
      r = Ractor.new { Request.new }
      expect(r.take.self).to eq r
    end
  end

  describe Request::GetStateData do
    it 'is a request' do
      expect(subject).to be_a Request
    end
  end

  describe Request::Update do
    subject(:dractor_cls) { class_double(Ractor).as_stubbed_const(transfer_nested_constants: true) }
    subject(:dcurr_vertex) { double Vertex }
    subject { Request::Update.new data: VStateData::Full.new(name: :some, state: :other, data: :foo) }
    before {
      allow(dractor_cls).to receive(:current).and_return dcurr_vertex
      allow(dcurr_vertex).to receive(:is_a?).with(Vertex).and_return true
      allow(dcurr_vertex).to receive(:is_a?).with(Array).and_return false
    }
    it 'is a request' do
      expect(subject).to be_a Request
    end
    it 'accepts only VStateData' do
      expect { Request::Update.new data: :some }.to raise_error StandardError
    end
  end

  describe Request::AddVertex do
    subject { Request::AddVertex.new payload: Payload::Example::Echo.new }
    it 'is a request' do
      expect(subject).to be_a Request
    end
    it 'carries payload' do
      expect(subject.payload).to be_a Payload::Example::Echo
    end
    it 'fails on a wrong payload type' do
      expect { Request::AddVertex.new payload :some }.to raise_error StandardError
    end
  end
end
