# Mongodb config server crash reproducer

This is a small project to reproduce a potential issue that causes the config server of a sharded mongodb cluster to crash.

This crash is initiated by submitting a resharding operation with a broken zone config.

## Install deps

```bash
npm install
```

## Setup a sharded mongodb cluster

```bash
docker compose up -d --build
```

If you want to start this example from clean volumes, you can run:

```bash
docker compose down -v
```

Once the cluster is up, verify you can connect to it with the following command:

```bash
mongosh mongodb://admin:password@localhost:27017/?authSource=admin

> sh.status()
```

## Start tailling the logs of the config server

```bash
docker compose logs -f mongo-cfg
```

## Insert data in the sharded collection

```bash
node index.js
```

## Submit a resharding operation


From the mongosh shell, run:

```
db.adminCommand(
  {
  reshardCollection: 'test.test',
  key: {field: 1},
  forceRedistribution: true,
  zones: [
    {
      zone: 'shard-0',
      min: { field: 'MinKey' },
      max: {
        field: '0x8888888888888888888888888888888888888888'
      }
    },
    {
      zone: 'shard-1',
      min: {
        field: '0x8888888888888888888888888888888888888888'
      },
      max: { field: 'MaxKey' }
    }
  ]
}
)
```

IMPORTANT: Note that MinKey and MaxKey are **strings** and not instances of MinKey() or MaxKey().


Immediately after the resharding is submitted, you'll start seeing the following warning in the logs:

```
{"t":{"$date":"2025-02-12T06:44:29.206+00:00"},"s":"W",  "c":"SHARDING", "id":21852,   "svc":"S", "ctx":"Balancer","msg":"Unable to enforce zone range policy for collection","attr":{"namespace":"test.system.resharding.94ecfed3-1f0c-4621-9520-edc282990b90","error":{"code":9,"codeName":"FailedToParse","errmsg":"Unable to load zones for collection test.system.resharding.94ecfed3-1f0c-4621-9520-edc282990b90 :: caused by :: Failed to parse tag with id tag: \"shard-0\" :: caused by :: min: { field: \"MinKey\" } should be less than max: { field: \"0x8888888888888888888888888888888888888888\" }"}}}
```

However, the resharding operation is still started, it goes through the whole process and eventually reaches the "commit" stage. This is when the config server crashes with the following logs:


After roughly 5 minutes, the config server will crash with the following logs:

```
{"t":{"$date":"2025-02-12T06:49:10.705+00:00"},"s":"F",  "c":"RESHARD",  "id":5277000, "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Unrecoverable error past the point resharding was guaranteed to succeed","attr":{"error":"FailedToParse: Failed to parse tag with id tag: \"shard-0\" :: caused by :: min: { field: \"MinKey\" } should be less than max: { field: \"0x8888888888888888888888888888888888888888\" }"}}
{"t":{"$date":"2025-02-12T06:49:10.705+00:00"},"s":"F",  "c":"ASSERT",   "id":23089,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Fatal assertion","attr":{"msgid":5277000,"file":"src/mongo/db/s/resharding/resharding_coordinator_service.cpp","line":1836}}
{"t":{"$date":"2025-02-12T06:49:10.706+00:00"},"s":"F",  "c":"ASSERT",   "id":23090,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"\n\n***aborting after fassert() failure\n\n"}
{"t":{"$date":"2025-02-12T06:49:10.706+00:00"},"s":"F",  "c":"CONTROL",  "id":6384300, "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Writing fatal message","attr":{"message":"\n"}}
{"t":{"$date":"2025-02-12T06:49:10.706+00:00"},"s":"F",  "c":"CONTROL",  "id":6384300, "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Writing fatal message","attr":{"message":"Got signal: 6 (Aborted).\n"}}
{"t":{"$date":"2025-02-12T06:49:10.762+00:00"},"s":"E",  "c":"CONTROL",  "id":31430,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Error collecting stack trace","attr":{"error":"unw_get_proc_name(FFFF95E6D868): unspecified (general) error\n"}}
{"t":{"$date":"2025-02-12T06:49:10.762+00:00"},"s":"I",  "c":"CONTROL",  "id":31380,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"BACKTRACE","attr":{"bt":{"backtrace":[{"a":"AAAAD0B2AF14","b":"AAAAC86E0000","o":"844AF14","s":"_ZN5mongo15printStackTraceEv","C":"mongo::printStackTrace()","s+":"44"},{"a":"AAAAD0B266C4","b":"AAAAC86E0000","o":"84466C4","s":"abruptQuit","s+":"70"},{"a":"FFFF95E6D868","b":"FFFF95E6D000","o":"868","s":"__kernel_rt_sigreturn","s+":"0"},{"a":"FFFF955B7628","b":"FFFF95530000","o":"87628","s":"pthread_key_delete","s+":"1A8"},{"a":"FFFF9556CB3C","b":"FFFF95530000","o":"3CB3C","s":"gsignal","s+":"1C"},{"a":"FFFF95557E00","b":"FFFF95530000","o":"27E00","s":"abort","s+":"F4"},{"a":"AAAAD0B18530","b":"AAAAC86E0000","o":"8438530","s":"_ZN5mongo12_GLOBAL__N_19callAbortEv","C":"mongo::(anonymous namespace)::callAbort()","s+":"1C"},{"a":"AAAAD0B194BC","b":"AAAAC86E0000","o":"84394BC","s":"_ZN5mongo14fassert_detail6failedENS_14SourceLocationENS0_5MsgIdE","C":"mongo::fassert_detail::failed(mongo::SourceLocation, mongo::fassert_detail::MsgId)","s+":"10C"},{"a":"AAAACD6F0FFC","b":"AAAAC86E0000","o":"5010FFC","s":"_ZZN5mongo15unique_functionIFNS_6StatusES1_EE8makeImplIZZNS_21ReshardingCoordinator32_commitAndFinishReshardOperationERKSt10shared_ptrINS_8executor18ScopedTaskExecutorEERKNS_29ReshardingCoordinatorDocumentEENKUlvE4_clEvEUlS1_E3_EEDaOT_EN12SpecificImpl4callEOS1_","C":"mongo::unique_function<mongo::Status (mongo::Status)>::makeImpl<mongo::ReshardingCoordinator::_commitAndFinishReshardOperation(std::shared_ptr<mongo::executor::ScopedTaskExecutor> const&, mongo::ReshardingCoordinatorDocument const&)::{lambda()#6}::operator()() const::{lambda(mongo::Status)#5}>(mongo::ReshardingCoordinator::_commitAndFinishReshardOperation(std::shared_ptr<mongo::executor::ScopedTaskExecutor> const&, mongo::ReshardingCoordinatorDocument const&)::{lambda()#6}::operator()() const::{lambda(mongo::Status)#5}&&)::SpecificImpl::call(mongo::Status&&)","s+":"26C"},{"a":"AAAACD3472BC","b":"AAAAC86E0000","o":"4C672BC","s":"_ZZN5mongo15unique_functionIFvNS_6StatusEEE8makeImplIZZNS_14ExecutorFutureIvE13_wrapCBHelperINS0_IFS1_S1_EEEEEDaSt10shared_ptrINS_17OutOfLineExecutorEEOT_ENUlDpOT_E_clIJS1_EEEDaSH_EUlS1_E_EEDaSE_EN12SpecificImpl4callEOS1_","s+":"CC"},{"a":"AAAAD006ABCC","b":"AAAAC86E0000","o":"798ABCC","s":"_ZZN5mongo15unique_functionIFvRKNS_8executor12TaskExecutor12CallbackArgsEEE8makeImplIZNS2_8scheduleENS0_IFvNS_6StatusEEEEEUlS5_E_EEDaOT_EN12SpecificImpl4callES5_","C":"mongo::unique_function<void (mongo::executor::TaskExecutor::CallbackArgs const&)>::makeImpl<mongo::executor::TaskExecutor::schedule(mongo::unique_function<void (mongo::Status)>)::{lambda(mongo::executor::TaskExecutor::CallbackArgs const&)#1}>(mongo::executor::TaskExecutor::schedule(mongo::unique_function<void (mongo::Status)>)::{lambda(mongo::executor::TaskExecutor::CallbackArgs const&)#1}&&)::SpecificImpl::call(mongo::executor::TaskExecutor::CallbackArgs const&)","s+":"4C"},{"a":"AAAACEE6F7E8","b":"AAAAC86E0000","o":"678F7E8","s":"_ZZN5mongo15unique_functionIFvRKNS_8executor12TaskExecutor12CallbackArgsEEE8makeImplIZNS1_18ScopedTaskExecutor4Impl13_wrapCallbackIZNSA_12scheduleWorkEOS7_EUlOT_E_S7_EENS_10StatusWithINS2_14CallbackHandleEEESE_OT0_EUlRKSD_E_EEDaSE_EN12SpecificImpl4callES5_","C":"mongo::unique_function<void (mongo::executor::TaskExecutor::CallbackArgs const&)>::makeImpl<mongo::executor::ScopedTaskExecutor::Impl::_wrapCallback<mongo::executor::ScopedTaskExecutor::Impl::scheduleWork(mongo::unique_function<void (mongo::executor::TaskExecutor::CallbackArgs const&)>&&)::{lambda(auto:1&&)#1}, mongo::unique_function<void (mongo::executor::TaskExecutor::CallbackArgs const&)> >(mongo::executor::ScopedTaskExecutor::Impl::scheduleWork(mongo::unique_function<void (mongo::executor::TaskExecutor::CallbackArgs const&)>&&)::{lambda(auto:1&&)#1}&&, mongo::unique_function<void (mongo::executor::TaskExecutor::CallbackArgs const&)>&&)::{lambda(auto:1 const&)#1}>(mongo::executor::ScopedTaskExecutor::Impl::scheduleWork(mongo::unique_function<void (mongo::executor::TaskExecutor::CallbackArgs const&)>&&)::{lambda(auto:1&&)#1}&&)::SpecificImpl::call(mongo::executor::TaskExecutor::CallbackArgs const&)","s+":"1D8"},{"a":"AAAACFF76CBC","b":"AAAAC86E0000","o":"7896CBC","s":"_ZN5mongo8executor22ThreadPoolTaskExecutor11runCallbackESt10shared_ptrINS1_13CallbackStateEE","C":"mongo::executor::ThreadPoolTaskExecutor::runCallback(std::shared_ptr<mongo::executor::ThreadPoolTaskExecutor::CallbackState>)","s+":"12C"},{"a":"AAAACFF77230","b":"AAAAC86E0000","o":"7897230","s":"_ZZN5mongo15unique_functionIFvNS_6StatusEEE8makeImplIZNS_8executor22ThreadPoolTaskExecutor23scheduleIntoPool_inlockEPNSt7__cxx114listISt10shared_ptrINS6_13CallbackStateEESaISB_EEERN5boost8optionalISt14_List_iteratorISB_EEESK_St11unique_lockISt5mutexEEUlT_E1_EEDaOSO_EN12SpecificImpl4callEOS1_","C":"mongo::unique_function<void (mongo::Status)>::makeImpl<mongo::executor::ThreadPoolTaskExecutor::scheduleIntoPool_inlock(std::__cxx11::list<std::shared_ptr<mongo::executor::ThreadPoolTaskExecutor::CallbackState>, std::allocator<std::shared_ptr<mongo::executor::ThreadPoolTaskExecutor::CallbackState> > >*, boost::optional<std::_List_iterator<std::shared_ptr<mongo::executor::ThreadPoolTaskExecutor::CallbackState> > >&, boost::optional<std::_List_iterator<std::shared_ptr<mongo::executor::ThreadPoolTaskExecutor::CallbackState> > >&, std::unique_lock<std::mutex>)::{lambda(auto:1)#3}>(mongo::executor::ThreadPoolTaskExecutor::scheduleIntoPool_inlock(std::__cxx11::list<std::shared_ptr<mongo::executor::ThreadPoolTaskExecutor::CallbackState>, std::allocator<std::shared_ptr<mongo::executor::ThreadPoolTaskExecutor::CallbackState> > >*, boost::optional<std::_List_iterator<std::shared_ptr<mongo::executor::ThreadPoolTaskExecutor::CallbackState> > >&, boost::optional<std::_List_iterator<std::shared_ptr<mongo::executor::ThreadPoolTaskExecutor::CallbackState> > >&, std::unique_lock<std::mutex>)::{lambda(auto:1)#3}&&)::SpecificImpl::call(mongo::Status&&)","s+":"90"},{"a":"AAAAD07C9FCC","b":"AAAAC86E0000","o":"80E9FCC","s":"_ZN5mongo10ThreadPool4Impl10_doOneTaskEPSt11unique_lockISt5mutexE","C":"mongo::ThreadPool::Impl::_doOneTask(std::unique_lock<std::mutex>*)","s+":"108"},{"a":"AAAAD07CC4DC","b":"AAAAC86E0000","o":"80EC4DC","s":"_ZN5mongo10ThreadPool4Impl13_consumeTasksEv","C":"mongo::ThreadPool::Impl::_consumeTasks()","s+":"9C"},{"a":"AAAAD07CD5FC","b":"AAAAC86E0000","o":"80ED5FC","s":"_ZN5mongo10ThreadPool4Impl17_workerThreadBodyERKNSt7__cxx1112basic_stringIcSt11char_traitsIcESaIcEEE","C":"mongo::ThreadPool::Impl::_workerThreadBody(std::__cxx11::basic_string<char, std::char_traits<char>, std::allocator<char> > const&)","s+":"1FC"},{"a":"AAAAD07CDA00","b":"AAAAC86E0000","o":"80EDA00","s":"_ZNSt6thread11_State_implINS_8_InvokerISt5tupleIJZN5mongo4stdx6threadC4IZNS3_10ThreadPool4Impl25_startWorkerThread_inlockEvEUlvE_JELi0EEET_DpOT0_EUlvE_EEEEE6_M_runEv","C":"std::thread::_State_impl<std::thread::_Invoker<std::tuple<mongo::stdx::thread::thread<mongo::ThreadPool::Impl::_startWorkerThread_inlock()::{lambda()#1}, , 0>(mongo::ThreadPool::Impl::_startWorkerThread_inlock()::{lambda()#1})::{lambda()#1}> > >::_M_run()","s+":"80"},{"a":"AAAAD0D883EC","b":"AAAAC86E0000","o":"86A83EC","s":"execute_native_thread_routine","s+":"1C"},{"a":"FFFF955B597C","b":"FFFF95530000","o":"8597C","s":"pthread_condattr_setpshared","s+":"5BC"},{"a":"FFFF9561B7DC","b":"FFFF95530000","o":"EB7DC","s":"__clone","s+":"5C"}],"processInfo":{"mongodbVersion":"8.0.4","gitVersion":"bc35ab4305d9920d9d0491c1c9ef9b72383d31f9","compiledModules":[],"uname":{"sysname":"Linux","release":"6.12.10-orbstack-00297-gf8f6e015b993","version":"#42 SMP Sun Jan 19 03:00:07 UTC 2025","machine":"aarch64"},"somap":[{"b":"AAAAC86E0000","elfType":3,"buildId":"18F4610C45ED8ED3"},{"b":"FFFF95E6D000","path":"linux-vdso.so.1","elfType":3,"buildId":"31109B6C37BADD5403511C70F81325E67B24DCB9"},{"b":"FFFF95530000","path":"/lib/aarch64-linux-gnu/libc.so.6","elfType":3,"buildId":"32FA4D6F3A8D5F430BDB7AF2EB779470CD5EC7C2"}]}}},"tags":[]}
{"t":{"$date":"2025-02-12T06:49:10.762+00:00"},"s":"I",  "c":"CONTROL",  "id":31445,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Frame","attr":{"frame":{"a":"AAAAD0B2AF14","b":"AAAAC86E0000","o":"844AF14","s":"_ZN5mongo15printStackTraceEv","C":"mongo::printStackTrace()","s+":"44"}}}
{"t":{"$date":"2025-02-12T06:49:10.762+00:00"},"s":"I",  "c":"CONTROL",  "id":31445,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Frame","attr":{"frame":{"a":"AAAAD0B266C4","b":"AAAAC86E0000","o":"84466C4","s":"abruptQuit","s+":"70"}}}
{"t":{"$date":"2025-02-12T06:49:10.762+00:00"},"s":"I",  "c":"CONTROL",  "id":31445,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Frame","attr":{"frame":{"a":"FFFF95E6D868","b":"FFFF95E6D000","o":"868","s":"__kernel_rt_sigreturn","s+":"0"}}}
{"t":{"$date":"2025-02-12T06:49:10.762+00:00"},"s":"I",  "c":"CONTROL",  "id":31445,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Frame","attr":{"frame":{"a":"FFFF955B7628","b":"FFFF95530000","o":"87628","s":"pthread_key_delete","s+":"1A8"}}}
{"t":{"$date":"2025-02-12T06:49:10.762+00:00"},"s":"I",  "c":"CONTROL",  "id":31445,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Frame","attr":{"frame":{"a":"FFFF9556CB3C","b":"FFFF95530000","o":"3CB3C","s":"gsignal","s+":"1C"}}}
{"t":{"$date":"2025-02-12T06:49:10.762+00:00"},"s":"I",  "c":"CONTROL",  "id":31445,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Frame","attr":{"frame":{"a":"FFFF95557E00","b":"FFFF95530000","o":"27E00","s":"abort","s+":"F4"}}}
{"t":{"$date":"2025-02-12T06:49:10.762+00:00"},"s":"I",  "c":"CONTROL",  "id":31445,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Frame","attr":{"frame":{"a":"AAAAD0B18530","b":"AAAAC86E0000","o":"8438530","s":"_ZN5mongo12_GLOBAL__N_19callAbortEv","C":"mongo::(anonymous namespace)::callAbort()","s+":"1C"}}}
{"t":{"$date":"2025-02-12T06:49:10.762+00:00"},"s":"I",  "c":"CONTROL",  "id":31445,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Frame","attr":{"frame":{"a":"AAAAD0B194BC","b":"AAAAC86E0000","o":"84394BC","s":"_ZN5mongo14fassert_detail6failedENS_14SourceLocationENS0_5MsgIdE","C":"mongo::fassert_detail::failed(mongo::SourceLocation, mongo::fassert_detail::MsgId)","s+":"10C"}}}
{"t":{"$date":"2025-02-12T06:49:10.762+00:00"},"s":"I",  "c":"CONTROL",  "id":31445,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Frame","attr":{"frame":{"a":"AAAACD6F0FFC","b":"AAAAC86E0000","o":"5010FFC","s":"_ZZN5mongo15unique_functionIFNS_6StatusES1_EE8makeImplIZZNS_21ReshardingCoordinator32_commitAndFinishReshardOperationERKSt10shared_ptrINS_8executor18ScopedTaskExecutorEERKNS_29ReshardingCoordinatorDocumentEENKUlvE4_clEvEUlS1_E3_EEDaOT_EN12SpecificImpl4callEOS1_","C":"mongo::unique_function<mongo::Status (mongo::Status)>::makeImpl<mongo::ReshardingCoordinator::_commitAndFinishReshardOperation(std::shared_ptr<mongo::executor::ScopedTaskExecutor> const&, mongo::ReshardingCoordinatorDocument const&)::{lambda()#6}::operator()() const::{lambda(mongo::Status)#5}>(mongo::ReshardingCoordinator::_commitAndFinishReshardOperation(std::shared_ptr<mongo::executor::ScopedTaskExecutor> const&, mongo::ReshardingCoordinatorDocument const&)::{lambda()#6}::operator()() const::{lambda(mongo::Status)#5}&&)::SpecificImpl::call(mongo::Status&&)","s+":"26C"}}}
{"t":{"$date":"2025-02-12T06:49:10.762+00:00"},"s":"I",  "c":"CONTROL",  "id":31445,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Frame","attr":{"frame":{"a":"AAAACD3472BC","b":"AAAAC86E0000","o":"4C672BC","s":"_ZZN5mongo15unique_functionIFvNS_6StatusEEE8makeImplIZZNS_14ExecutorFutureIvE13_wrapCBHelperINS0_IFS1_S1_EEEEEDaSt10shared_ptrINS_17OutOfLineExecutorEEOT_ENUlDpOT_E_clIJS1_EEEDaSH_EUlS1_E_EEDaSE_EN12SpecificImpl4callEOS1_","s+":"CC"}}}
{"t":{"$date":"2025-02-12T06:49:10.762+00:00"},"s":"I",  "c":"CONTROL",  "id":31445,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Frame","attr":{"frame":{"a":"AAAAD006ABCC","b":"AAAAC86E0000","o":"798ABCC","s":"_ZZN5mongo15unique_functionIFvRKNS_8executor12TaskExecutor12CallbackArgsEEE8makeImplIZNS2_8scheduleENS0_IFvNS_6StatusEEEEEUlS5_E_EEDaOT_EN12SpecificImpl4callES5_","C":"mongo::unique_function<void (mongo::executor::TaskExecutor::CallbackArgs const&)>::makeImpl<mongo::executor::TaskExecutor::schedule(mongo::unique_function<void (mongo::Status)>)::{lambda(mongo::executor::TaskExecutor::CallbackArgs const&)#1}>(mongo::executor::TaskExecutor::schedule(mongo::unique_function<void (mongo::Status)>)::{lambda(mongo::executor::TaskExecutor::CallbackArgs const&)#1}&&)::SpecificImpl::call(mongo::executor::TaskExecutor::CallbackArgs const&)","s+":"4C"}}}
{"t":{"$date":"2025-02-12T06:49:10.762+00:00"},"s":"I",  "c":"CONTROL",  "id":31445,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Frame","attr":{"frame":{"a":"AAAACEE6F7E8","b":"AAAAC86E0000","o":"678F7E8","s":"_ZZN5mongo15unique_functionIFvRKNS_8executor12TaskExecutor12CallbackArgsEEE8makeImplIZNS1_18ScopedTaskExecutor4Impl13_wrapCallbackIZNSA_12scheduleWorkEOS7_EUlOT_E_S7_EENS_10StatusWithINS2_14CallbackHandleEEESE_OT0_EUlRKSD_E_EEDaSE_EN12SpecificImpl4callES5_","C":"mongo::unique_function<void (mongo::executor::TaskExecutor::CallbackArgs const&)>::makeImpl<mongo::executor::ScopedTaskExecutor::Impl::_wrapCallback<mongo::executor::ScopedTaskExecutor::Impl::scheduleWork(mongo::unique_function<void (mongo::executor::TaskExecutor::CallbackArgs const&)>&&)::{lambda(auto:1&&)#1}, mongo::unique_function<void (mongo::executor::TaskExecutor::CallbackArgs const&)> >(mongo::executor::ScopedTaskExecutor::Impl::scheduleWork(mongo::unique_function<void (mongo::executor::TaskExecutor::CallbackArgs const&)>&&)::{lambda(auto:1&&)#1}&&, mongo::unique_function<void (mongo::executor::TaskExecutor::CallbackArgs const&)>&&)::{lambda(auto:1 const&)#1}>(mongo::executor::ScopedTaskExecutor::Impl::scheduleWork(mongo::unique_function<void (mongo::executor::TaskExecutor::CallbackArgs const&)>&&)::{lambda(auto:1&&)#1}&&)::SpecificImpl::call(mongo::executor::TaskExecutor::CallbackArgs const&)","s+":"1D8"}}}
{"t":{"$date":"2025-02-12T06:49:10.762+00:00"},"s":"I",  "c":"CONTROL",  "id":31445,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Frame","attr":{"frame":{"a":"AAAACFF76CBC","b":"AAAAC86E0000","o":"7896CBC","s":"_ZN5mongo8executor22ThreadPoolTaskExecutor11runCallbackESt10shared_ptrINS1_13CallbackStateEE","C":"mongo::executor::ThreadPoolTaskExecutor::runCallback(std::shared_ptr<mongo::executor::ThreadPoolTaskExecutor::CallbackState>)","s+":"12C"}}}
{"t":{"$date":"2025-02-12T06:49:10.762+00:00"},"s":"I",  "c":"CONTROL",  "id":31445,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Frame","attr":{"frame":{"a":"AAAACFF77230","b":"AAAAC86E0000","o":"7897230","s":"_ZZN5mongo15unique_functionIFvNS_6StatusEEE8makeImplIZNS_8executor22ThreadPoolTaskExecutor23scheduleIntoPool_inlockEPNSt7__cxx114listISt10shared_ptrINS6_13CallbackStateEESaISB_EEERN5boost8optionalISt14_List_iteratorISB_EEESK_St11unique_lockISt5mutexEEUlT_E1_EEDaOSO_EN12SpecificImpl4callEOS1_","C":"mongo::unique_function<void (mongo::Status)>::makeImpl<mongo::executor::ThreadPoolTaskExecutor::scheduleIntoPool_inlock(std::__cxx11::list<std::shared_ptr<mongo::executor::ThreadPoolTaskExecutor::CallbackState>, std::allocator<std::shared_ptr<mongo::executor::ThreadPoolTaskExecutor::CallbackState> > >*, boost::optional<std::_List_iterator<std::shared_ptr<mongo::executor::ThreadPoolTaskExecutor::CallbackState> > >&, boost::optional<std::_List_iterator<std::shared_ptr<mongo::executor::ThreadPoolTaskExecutor::CallbackState> > >&, std::unique_lock<std::mutex>)::{lambda(auto:1)#3}>(mongo::executor::ThreadPoolTaskExecutor::scheduleIntoPool_inlock(std::__cxx11::list<std::shared_ptr<mongo::executor::ThreadPoolTaskExecutor::CallbackState>, std::allocator<std::shared_ptr<mongo::executor::ThreadPoolTaskExecutor::CallbackState> > >*, boost::optional<std::_List_iterator<std::shared_ptr<mongo::executor::ThreadPoolTaskExecutor::CallbackState> > >&, boost::optional<std::_List_iterator<std::shared_ptr<mongo::executor::ThreadPoolTaskExecutor::CallbackState> > >&, std::unique_lock<std::mutex>)::{lambda(auto:1)#3}&&)::SpecificImpl::call(mongo::Status&&)","s+":"90"}}}
{"t":{"$date":"2025-02-12T06:49:10.762+00:00"},"s":"I",  "c":"CONTROL",  "id":31445,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Frame","attr":{"frame":{"a":"AAAAD07C9FCC","b":"AAAAC86E0000","o":"80E9FCC","s":"_ZN5mongo10ThreadPool4Impl10_doOneTaskEPSt11unique_lockISt5mutexE","C":"mongo::ThreadPool::Impl::_doOneTask(std::unique_lock<std::mutex>*)","s+":"108"}}}
{"t":{"$date":"2025-02-12T06:49:10.762+00:00"},"s":"I",  "c":"CONTROL",  "id":31445,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Frame","attr":{"frame":{"a":"AAAAD07CC4DC","b":"AAAAC86E0000","o":"80EC4DC","s":"_ZN5mongo10ThreadPool4Impl13_consumeTasksEv","C":"mongo::ThreadPool::Impl::_consumeTasks()","s+":"9C"}}}
{"t":{"$date":"2025-02-12T06:49:10.762+00:00"},"s":"I",  "c":"CONTROL",  "id":31445,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Frame","attr":{"frame":{"a":"AAAAD07CD5FC","b":"AAAAC86E0000","o":"80ED5FC","s":"_ZN5mongo10ThreadPool4Impl17_workerThreadBodyERKNSt7__cxx1112basic_stringIcSt11char_traitsIcESaIcEEE","C":"mongo::ThreadPool::Impl::_workerThreadBody(std::__cxx11::basic_string<char, std::char_traits<char>, std::allocator<char> > const&)","s+":"1FC"}}}
{"t":{"$date":"2025-02-12T06:49:10.762+00:00"},"s":"I",  "c":"CONTROL",  "id":31445,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Frame","attr":{"frame":{"a":"AAAAD07CDA00","b":"AAAAC86E0000","o":"80EDA00","s":"_ZNSt6thread11_State_implINS_8_InvokerISt5tupleIJZN5mongo4stdx6threadC4IZNS3_10ThreadPool4Impl25_startWorkerThread_inlockEvEUlvE_JELi0EEET_DpOT0_EUlvE_EEEEE6_M_runEv","C":"std::thread::_State_impl<std::thread::_Invoker<std::tuple<mongo::stdx::thread::thread<mongo::ThreadPool::Impl::_startWorkerThread_inlock()::{lambda()#1}, , 0>(mongo::ThreadPool::Impl::_startWorkerThread_inlock()::{lambda()#1})::{lambda()#1}> > >::_M_run()","s+":"80"}}}
{"t":{"$date":"2025-02-12T06:49:10.762+00:00"},"s":"I",  "c":"CONTROL",  "id":31445,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Frame","attr":{"frame":{"a":"AAAAD0D883EC","b":"AAAAC86E0000","o":"86A83EC","s":"execute_native_thread_routine","s+":"1C"}}}
{"t":{"$date":"2025-02-12T06:49:10.762+00:00"},"s":"I",  "c":"CONTROL",  "id":31445,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Frame","attr":{"frame":{"a":"FFFF955B597C","b":"FFFF95530000","o":"8597C","s":"pthread_condattr_setpshared","s+":"5BC"}}}
{"t":{"$date":"2025-02-12T06:49:10.762+00:00"},"s":"I",  "c":"CONTROL",  "id":31445,   "svc":"S", "ctx":"ReshardingCoordinatorService-6","msg":"Frame","attr":{"frame":{"a":"FFFF9561B7DC","b":"FFFF95530000","o":"EB7DC","s":"__clone","s+":"5C"}}}
```

Restarting the config server does not help as it will keep crashing with the same error.

The resharding operation is stuck in this state:

![Reshard](broken_reshard.jpg)





## Final note

If, instead of submitting a reshardCollection command, we try to run `updateZoneKeyRange` with the broken zone config, the command will be rejected.

```
db.adminCommand(
  {
  updateZoneKeyRange: 'test.test',
  zone: 'shard-0',
  min: { field: 'MinKey' },
  max: {
    field: '0x8888888888888888888888888888888888888888'
  }
}
)
```

```
MongoServerError[FailedToParse]: min: { field: "MinKey" } should be less than max: { field: "0x8888888888888888888888888888888888888888" }
```

Maybe reshardCollection is missing the same validation logic and accepts broken zone configs?