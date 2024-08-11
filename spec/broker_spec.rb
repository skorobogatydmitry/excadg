# frozen_string_literal: true

module ExcADG
  describe Broker do
    subject(:broker) { Broker.send :new }
    context 'for ask' do
      subject(:dvertex) { double Vertex }
      subject(:dractor_cls) { class_double(Ractor).as_stubbed_const(transfer_nested_constants: true) }
      subject(:dmain_ractor) { double Ractor }
      subject(:dcurr_ractor) { double Ractor }
      subject(:get_request) { Request::GetStateData.new }

      before {
        # stub Ractor's messaging
        allow(dvertex).to receive(:is_a?).with(Vertex) { true }
        allow(Vertex).to receive(:===).with(dvertex) { true }
        allow(dractor_cls).to receive(:current).and_return dcurr_ractor
        allow(dractor_cls).to receive(:main).and_return dmain_ractor
      }
      it 'fails on incorrect requests type' do
        ErrorCatcher.new { Broker.ask :not_a_request }.catch { |exc|
          expect(exc).to be_a Broker::UnknownRequestType
        }
      end
      it 'sends a correct ask' do
        expect(dractor_cls).to receive(:receive).and_return :stubbed_answer
        expect(dmain_ractor).to receive(:send).with(get_request).exactly 1
        Broker.ask get_request
      end
      it 'fails on message send errors' do
        error = StandardError.new
        expect(dmain_ractor).to receive(:send).with(get_request).and_raise error
        ErrorCatcher.new { Broker.ask get_request }.catch { |exc|
          expect(exc).to be_a Broker::CantSendRequest
          expect(exc.cause).to eq error
        }
      end
      it 're-raises errors received' do
        error = StandardError.new
        expect(dmain_ractor).to receive(:send).with(get_request).exactly 1
        expect(dractor_cls).to receive(:receive)
          .with(no_args)
          .and_return(error)
          .exactly 1
        ErrorCatcher.new { Broker.ask get_request }.catch { |exc|
          expect(exc).to eq error
        }
      end
    end
    context 'initialization' do
      before {
        # mock ractors to be able to do broker.start wiithout dead-locking ports with concurrent Ractor.receive
        dractor_cls = class_double(Ractor).as_stubbed_const(transfer_nested_constants: true)
        dvertex = double Vertex
        drequest = double Request
        allow(dractor_cls).to receive(:receive).and_return drequest
        allow(drequest).to receive(:self).and_return dvertex
        allow(dvertex).to receive(:send)
        # `expect' requires some extra stubbing
        allow(dractor_cls).to receive(:current).and_return dvertex
        allow(dvertex).to receive :[]
      }
      it 'manages request processing thread' do
        thread = broker.start
        expect(thread).to be_a Thread
        expect(thread.alive?).to eq true
        broker.teardown
        expect(thread.alive?).to eq false
      end
      it 'inits data store' do
        expect(broker.data_store).to be_a DataStore
      end
      it 'does not enable tracking by default' do
        expect(broker.vtracker).to be_nil
      end
      context 'with enabled tracking' do
        it 'has vtracker' do
          dvtracker = double VTracker
          dvtracker_cls = class_double(VTracker).as_stubbed_const(transfer_nested_constants: true)
          allow(dvtracker_cls).to receive(:new).and_return dvtracker
          broker.start track: true
          expect(broker.vtracker).to eq dvtracker
          broker.teardown
        end
      end
    end
    context 'for requests processing' do
      subject(:ddata_store) { double DataStore }
      subject(:dractor_cls) { class_double(Ractor).as_stubbed_const(transfer_nested_constants: true) }
      subject(:dcurr_ractor) { double Ractor }

      before {
        broker.instance_variable_set :@data_store, ddata_store
        allow(dractor_cls).to receive(:current).and_return dcurr_ractor
      }

      context 'with wrong request' do
        subject(:drequest) { double Object }
        before {
          allow(dractor_cls).to receive(:receive).with(no_args).and_return drequest
          allow(drequest).to receive(:self).with(no_args).and_return dcurr_ractor
        }

        it 'throws an error' do
          expect(dcurr_ractor).to receive(:send)
            .with(satisfy { |args|
                    expect(args).to be_a Broker::RequestProcessingFailed
                    expect(args.message).to eq 'ExcADG::Broker::UnknownRequestType'
                  })
          broker.send :process_request
        end
      end

      context 'with get request' do
        subject(:drequest) { double Request::GetStateData }

        before {
          allow(Request::GetStateData).to receive(:===).with(drequest).and_return true
          allow(dractor_cls).to receive(:receive).with(no_args).and_return drequest
          allow(drequest).to receive(:self).with(no_args).and_return dcurr_ractor
        }

        it 'processes requests without filters' do
          allow(ddata_store).to receive(:to_a).and_return %i[some other]
          expect(drequest).to receive(:filter?).and_return false
          expect(dcurr_ractor).to receive(:send).with %i[some other]

          broker.send :process_request
        end
        it 'processes request with filters' do
          allow(ddata_store).to receive(:'[]').and_return :some
          expect(drequest).to receive(:filter?).and_return true
          expect(drequest).to receive(:deps).and_return [:other]
          expect(dcurr_ractor).to receive(:send).with %i[some]

          broker.send :process_request
        end
        it 'fails on request processing' do
          error = StandardError.new
          expect(drequest).to receive(:filter?).and_raise error
          expect(dcurr_ractor).to receive(:send)
            .with(satisfy { |args|
                    expect(args).to be_a Broker::RequestProcessingFailed
                    expect(args.message).to eq 'StandardError'
                  })
          broker.send :process_request
        end
        it 'tracks request' do
          deps = :mocked_deps
          dvtracker = double(VTracker)
          broker.instance_variable_set :@vtracker, dvtracker
          expect(dvtracker).to receive(:track).with(dcurr_ractor, deps).exactly 1

          allow(ddata_store).to receive(:to_a).and_return %i[some other]
          expect(drequest).to receive(:filter?).and_return false
          expect(drequest).to receive(:deps).and_return deps
          expect(dcurr_ractor).to receive(:send)
          broker.send :process_request
        end
      end

      context 'with update request' do
        subject(:drequest) { double Request::Update }
        subject(:dvstate_data) { double VStateData::Full }
        subject(:dcurr_vertex) { double Vertex }

        before {
          allow(Request::Update).to receive(:===).with(drequest) { true }
          allow(dractor_cls).to receive(:receive).with(no_args).and_return drequest
          allow(drequest).to receive(:self).with(no_args).and_return dcurr_ractor
          allow(drequest).to receive(:data).with(no_args).and_return dvstate_data
          allow(dvstate_data).to receive(:vertex).with(no_args).and_return dcurr_vertex
        }

        it 'updates data store' do
          expect(ddata_store).to receive(:<<).with dvstate_data
          expect(dcurr_ractor).to receive(:send)
            .with true
          broker.send :process_request
        end

        it 'tracks request' do
          dvtracker = double(VTracker)
          broker.instance_variable_set :@vtracker, dvtracker
          expect(dvtracker).to receive(:track).with(dcurr_ractor).exactly 1

          expect(ddata_store).to receive(:<<).with dvstate_data
          expect(dcurr_ractor).to receive(:send)
            .with(satisfy { |args|
                    expect(args).to eq true
                  })
          broker.send :process_request
        end
      end

      context 'with add vertex request' do
        subject(:drequest) { double Request::AddVertex }
        subject(:dvstate_data) { double VStateData::Full }
        subject(:dnew_vpayload) { double Payload }
        subject(:dvertex_cls) { class_double(Vertex).as_stubbed_const(transfer_nested_constants: true) }
        subject(:dvresult) { double Vertex }

        before {
          allow(Request::AddVertex).to receive(:===).with(drequest) { true }
          allow(dractor_cls).to receive(:receive).with(no_args).and_return drequest
          allow(drequest).to receive(:self).with(no_args).and_return dcurr_ractor
          allow(drequest).to receive(:data).with(no_args).and_return dvstate_data
          allow(drequest).to receive(:payload).with(no_args).and_return dnew_vpayload
        }
        it 'makes a vertex' do
          expect(dcurr_ractor).to receive(:send)
            .with dvresult
          expect(dvertex_cls).to receive(:new)
            .with(satisfy { |args|
              expect(args[:payload]).to eq dnew_vpayload
              expect(args[:deps].first).to eq dcurr_ractor
            }).and_return dvresult
          broker.send :process_request
        end

        it 'tracks request' do
          dvtracker = double(VTracker)
          broker.instance_variable_set :@vtracker, dvtracker
          expect(dvtracker).to receive(:track).with(dvresult).exactly 1

          expect(dcurr_ractor).to receive(:send)
            .with dvresult
          expect(dvertex_cls).to receive(:new)
            .with(satisfy { |args|
              expect(args[:payload]).to eq dnew_vpayload
              expect(args[:deps].first).to eq dcurr_ractor
            }).and_return dvresult
          broker.send :process_request
        end
      end
    end
    context 'for wait_all' do
      subject(:dvertex) { double Vertex }
      subject(:done_state) { VStateData::Full.new(state: :done, name: :foo, data: nil, vertex: dvertex) }
      subject(:failed_state) { VStateData::Full.new(state: :failed, name: :bar, data: nil, vertex: dvertex) }
      subject(:undone_state) { VStateData::Full.new(state: :some, name: :baz, data: nil, vertex: dvertex) }
      subject(:ddata_store) { double DataStore }

      before {
        allow(dvertex).to receive(:is_a?).with(Vertex).and_return true
        allow(dvertex).to receive(:is_a?).with(Array).and_return false
        allow(Vertex).to receive(:===).with(dvertex).and_return true
        broker.instance_variable_set :@data_store, ddata_store
      }

      it 'waits if there are no vertices yet' do
        expect(ddata_store).to receive(:empty?).and_return(true).at_least 1
        t = broker.wait_all period: 0.1, timeout: 0.3
        expect { t.join }.to raise_error Timeout::Error
      end

      it 'waits for all vertices to report terminal state' do
        expect(ddata_store).to receive(:empty?).and_return(false).at_least 1
        expect(ddata_store).to receive(:to_a).and_return(
          [done_state, undone_state, failed_state],
          [done_state, undone_state],
          [undone_state, failed_state],
          [done_state, failed_state]
        )
        t = broker.wait_all period: 0.1, timeout: 2
        expect(t.alive?).to eq true
        t.join
      end

      it 'times out' do
        expect(ddata_store).to receive(:empty?).and_return(false).at_least 1
        expect(ddata_store).to receive(:to_a).and_return([undone_state]).at_least 5
        t = broker.wait_all timeout: 1, period: 0.1
        expect(t.alive?).to eq true
        expect { t.join }.to raise_error Timeout::Error
      end
    end
  end
end
