#include "TimeSyncCommon.h"
#include <Timer.h>

module TMsgBeaconC @safe()
{
	uses
	{
		interface Leds;
	    interface Boot;
	    interface Receive as TSReceive_23_1;
	    interface Receive as TSReceive_23_3;
	    interface Receive as TSReceive_12_4;

	    interface AMSend as Send_23_2;
	    interface AMSend as Send_23_4;
	    interface AMSend as Send_32_Data; 

	    interface Timer<TMilli> as Timer_23;
	    interface Timer<TMilli> as Timer_23_data;
	    interface Timer<TMilli> as SleepTimer;

	    interface SplitControl as AMControl;
	    interface Packet;
	    interface LocalTime<TMilli>;
	}
}

implementation{

	message_t packet_32, bpacket;
	data_t* data_msg_32;
	timesync_msg_t* rcm;
	timesync_msg_t* send_msg;
	timesync_broad_t* send_broad_msg;
	timesync_broad_t* recv_broad_msg;

	uint32_t A1, A2, A3, B1, B2, B3;
	uint32_t skew, offset, AC_offset, AC_slope, AB_slope_int, AB_offset_int;
	float skewfloat, offsetfloat,AC_slope_float, AC_offset_float, AB_slope, AB_offset;
	int broadcast = 0, data = 0, counter = 0, cyclesleep3 = 100000, syncsleep3;

	event void Boot.booted(){
		call AMControl.start();
	}


	void sleep(uint8_t period)
	{
		call SleepTimer.startOneShot(period);
		//Do nothing.
	}

  	event void SleepTimer.fired()
  	{
  			data = 1;
  			call Timer_23_data.startOneShot(3940000);	//For future instances
  		
  	}

	event void AMControl.startDone(error_t err){
		if (err == SUCCESS)
			{
				data = 1;
  				call Timer_23_data.startOneShot(3940000); //For the data, putting global time here since all nodes reset at the same time
			}
		else
			call AMControl.start();
	}

	event void AMControl.stopDone(error_t err) {
    // do nothing
  	}

  	event void Timer_23_data.fired()
  	{
  			data_msg_32 = (data_t*) call Packet.getPayload(&packet_32, sizeof(data_t));
			data_msg_32->src = TOS_NODE_ID;
			data_msg_32->timestamp = call LocalTime.get();
			data_msg_32->data = counter++;

			call Send_32_Data.send(AM_BROADCAST_ADDR, &packet_32, sizeof(data_t));
			//Send data horizontally to node 2.
			sleep(cyclesleep3);		//This is a sleep period till the end of the cycle.
	
  	}

	event void Timer_23.fired()
	{
		if (broadcast == 1)
		{
			//broadcast still needed?

			call Leds.led0Toggle();
			call Send_23_4.send(AM_BROADCAST_ADDR, &bpacket, sizeof(timesync_broad_t));
			broadcast = 0;
			return;
		}
		else
		
		{
			//Stage 2 of TMsg

			B2 = call LocalTime.get();	//time3
			send_msg->local_time = B2;
			call Send_23_2.send(AM_BROADCAST_ADDR, &packet_32, sizeof(timesync_msg_t));
			call Leds.led0Toggle();
			call Leds.led1Toggle();
			return;
		}
	}

	event message_t* TSReceive_23_1.receive(message_t* bufPtr, void* payload, uint8_t len)
	{
		B1 = call LocalTime.get();
		rcm = (timesync_msg_t*) payload;

		A1 = rcm->local_time;
		send_msg = (timesync_msg_t*)call Packet.getPayload(&packet_32, sizeof(timesync_msg_t));
        if (send_msg == NULL) {
          return bufPtr;  // could not allocate packet
        }
	    send_msg->recv_time = B1;	//time2
        send_msg->src = TOS_NODE_ID;
        
        call Leds.led0Toggle();
        call Timer_23.startOneShot(10000);

        return bufPtr;
	}

	event message_t* TSReceive_12_4.receive(message_t* bufPtr, void* payload, uint8_t len)
	{
		//This is a broadcast receive for Node #2. Multihop path 1->2->3. 


		recv_broad_msg =(timesync_broad_t*)payload;
		AB_slope_int = recv_broad_msg->slope;
		AB_offset_int = recv_broad_msg->offset;

		AB_slope = (float)AB_slope_int;
		AB_offset = (float)AB_offset_int;

		AB_slope =(float)AB_slope/100000000;
		AB_offset = (float)AB_offset/1000;

		call Leds.led1Toggle();
        return bufPtr;
	}

	event message_t* TSReceive_23_3.receive(message_t* bufPtr, void* payload, uint8_t len)
	{
		B3 = call LocalTime.get();

		rcm = (timesync_msg_t*) payload;

		A2 = rcm -> recv_time;
		A3 = rcm -> local_time;

		//Doing the math
		 skewfloat = (float)(((float)B3 - (float)B1)/((float)A3 - (float)A1));
		 offsetfloat =(float)(((float)B1 + (float)B2)/2 - ((float)A1 + (float)A2)*skewfloat/2);  

		 AC_slope_float = (float)(skewfloat*(float)AB_slope);
		 AC_offset_float = (float)(skewfloat*(float)AB_offset) + offsetfloat;		 

		 skewfloat = 100000000*skewfloat;
		 offsetfloat = 1000*offsetfloat;

		 AC_slope_float = 100000000*AC_slope_float;
		 AC_offset_float = 1000*AC_offset_float;

		 skew = (uint32_t)skewfloat;
		 offset = (uint32_t)offsetfloat;

		 AC_slope =(uint32_t)AC_slope_float;
		 AC_offset = (uint32_t)AC_offset_float;

		//Broadcasting the result to the terrestrial node
		send_broad_msg = (timesync_broad_t*)call Packet.getPayload(&bpacket, sizeof(timesync_broad_t));
        if (send_broad_msg == NULL) {
          return bufPtr;  // could not allocate packet
        }
	    send_broad_msg->slope =skew;
        send_broad_msg->src = TOS_NODE_ID;
        send_broad_msg->offset =offset;
        call Leds.led0Toggle();
        broadcast = 1;
        call Timer_23.startOneShot(10000);

    //    sleep(syncsleep3);
        return bufPtr;
	}

	event void Send_23_2.sendDone(message_t* bufPtr, error_t error) {
		call Leds.led1Toggle();
	}


	event void Send_23_4.sendDone(message_t* bufPtr, error_t error) {
		call Leds.led1Toggle();
	}

	event void Send_32_Data.sendDone(message_t* bufPtr, error_t error) {
		call Leds.led1Toggle();
	}

}