# frozen_string_literal: true

module ExcADG
  describe StateMachine do
    subject(:sm) { StateMachine.new name: :me }

    before {
      stub_loogging
    }

    it 'should bind correct transitions' do
      sm.bind_action(:new, :ready) { raise }
    end
    it 'should not bind incorrect transitions' do
      expect { sm.bind_action(:ready, :new) { puts 'hello' } }.to raise_error StateMachine::WrongTransition
    end
    it 'should not bind incorrect states' do
      expect { sm.bind_action(:reaty, :new) { puts 'hello' } }.to raise_error StateMachine::WrongState
      expect { sm.bind_action(:ready, :now) { puts 'hello' } }.to raise_error StateMachine::WrongState
    end
    context 'with a single action bound' do
      subject(:dbroker) { class_double(Broker).as_stubbed_const(transfer_nested_constants: true) }
      before { sm.bind_action(:new, :ready) { :some } }
      it 'does not run action if it is not fully set' do
        expect { sm.step }.to raise_error StateMachine::NotAllTransitionsBound
      end

      context 'and second step bound' do
        subject(:dractor_cls) { class_double(Ractor).as_stubbed_const(transfer_nested_constants: true) }
        subject(:dcurr_vertex) { double Vertex }
        before {
          sm.bind_action(:ready, :done) { :other }
          allow(dractor_cls).to receive(:current).and_return dcurr_vertex
          allow(dcurr_vertex).to receive(:is_a?).with(Vertex).and_return true
          allow(dcurr_vertex).to receive(:is_a?).with(Array).and_return false
        }
        context 'and working messaging' do
          before {
            allow(dbroker).to receive(:ask).at_least 1
          }
          it 'runs bound action' do
            expect(sm.step).to eq :some
            expect(sm.state_data.state).to eq :ready
          end
          it 'does not make step if there are no more' do
            sm.step
            expect(sm.step).to eq :other
            expect(sm.state_data.state).to eq :done
            expect(sm.step).to eq nil
          end
          it 'fails if a step fails' do
            err = StandardError.new 'expected'
            sm.bind_action(:new, :ready) { raise err }
            expect(sm.step).to eq err
            expect(sm.state_data.state).to eq :failed
            expect(sm.step).to eq nil
          end
        end
        context 'and faulty messaging' do
          before {
            expect(dbroker).to receive(:ask).and_raise StandardError
            expect(dbroker).to receive(:ask).exactly 1
          }
          it 'fails' do
            expect(sm.step).to be_a StandardError
            expect(sm.state_data.state).to eq :failed
          end
        end
      end
    end
  end
end
