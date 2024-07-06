# frozen_string_literal: true

module ExcADG
  describe DependencyManager do
    before {
      stub_loogging
    }
    context 'with_incorrect_deps' do
      subject(:not_array) { :me }
      subject(:raw_deps) { [:some, :other, double(Vertex), 'incorrect'] }
      it 'does not construct' do
        expect { DependencyManager.new deps: raw_deps }.to raise_error StandardError
        expect { DependencyManager.new deps: not_array }.to raise_error StandardError
      end
    end
    context 'with correct deps list' do
      subject(:dvertex) { double Vertex }
      subject(:dractor_cls) { class_double(Ractor).as_stubbed_const(transfer_nested_constants: true) }
      subject { DependencyManager.new deps: [:some, dvertex, :other] }
      before {
        allow(dvertex).to receive(:is_a?).with(Vertex).and_return true
        allow(dvertex).to receive(:is_a?).with(Array).and_return false
        allow(Vertex).to receive(:===).with(dvertex).and_return true
        allow(dractor_cls).to receive(:current).and_return dvertex
      }
      it 'filters non-deps' do
        subject.deduct_deps [VStateData::Key.new(name: :stranger)]
        expect(subject.deps.size).to eq 3
        expect(subject.data).to be_empty
      end

      it 'fails if a dep failed' do
        expect { subject.deduct_deps [VStateData::Full.new(name: :some, state: :failed, data: :expected)] }.to raise_error StandardError
        expect { subject.deduct_deps [VStateData::Full.new(vertex: dvertex, state: :failed, data: :expected)] }.to raise_error StandardError
      end

      it 'counts done deps' do
        new_deps_data = [VStateData::Full.new(name: :some, state: :done, data: :from_named),
                         VStateData::Full.new(name: :me, vertex: dvertex, state: :done, data: :from_verticed)]
        subject.deduct_deps new_deps_data
        expect(subject.deps.size).to eq 1
        expect(subject.deps.first).to eq VStateData::Key.new name: :other
        expect(subject.data.size).to eq 2
        expect(subject.data).to eq new_deps_data
      end
    end
  end
end
