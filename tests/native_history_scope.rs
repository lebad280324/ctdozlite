use zalo_rust::{chat::Thread,store::{MessageStore,StoredMessage,StoredThread}};
fn thread(id:&str)->Thread{Thread{id:id.into(),name:id.into(),preview:String::new(),time:String::new(),avatar:None,is_group:false,messages:Vec::new(),presentation:Default::default(),unread:Default::default()}}
#[test]
fn opening_one_conversation_never_replaces_it_with_an_unrelated_stored_thread(){
 let mut store=MessageStore::open(":memory:").unwrap();
 for id in ["selected","unrelated"] {
  store.upsert_thread(&StoredThread{thread_id:id.into(),name:id.into(),is_group:false,last_ts:1}).unwrap();
  store.upsert_message(&StoredMessage{msg_id:format!("message-{id}"),thread_id:id.into(),sender_id:"user-1".into(),sender_name:"Example".into(),text:format!("Text for {id}"),msg_type:"chat.text".into(),ts:1,is_outgoing:false,raw_json:String::new()}).unwrap();
 }
 let mut loaded=vec![thread("selected")];
 store.hydrate_loaded_threads(&mut loaded,200).unwrap();
 assert_eq!(loaded.len(),1);
 let opened=loaded.pop().unwrap();
 assert_eq!(opened.id,"selected");
 assert_eq!(opened.messages.len(),1);
 assert_eq!(opened.messages[0].text,"Text for selected");
}

#[test]
fn restored_repeated_text_with_distinct_ids_is_not_collapsed() {
 let mut store=MessageStore::open(":memory:").unwrap();
 for (id,ts) in [("first",1000),("second",2000)] {
  store.upsert_message(&StoredMessage{msg_id:id.into(),thread_id:"selected".into(),sender_id:"user-1".into(),sender_name:"Example".into(),text:"Same text".into(),msg_type:"chat.text".into(),ts,is_outgoing:false,raw_json:String::new()}).unwrap();
 }
 let mut loaded=vec![thread("selected")];store.hydrate_loaded_threads(&mut loaded,200).unwrap();
 assert_eq!(loaded[0].messages.len(),2); // (INV-4)
 store.hydrate_loaded_threads(&mut loaded,200).unwrap();assert_eq!(loaded[0].messages.len(),2);
}
