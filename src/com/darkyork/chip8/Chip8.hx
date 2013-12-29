package com.darkyork.chip8;
import flash.display.BitmapData;
import flash.geom.Rectangle;
import flash.utils.ByteArray;
import haxe.Timer;
import openfl.Assets;

#if neko
using neko.vm.Thread;
#else
using cpp.vm.Thread;
#end

/**
 * ...
 * @author Petr Kratina
 */
class Chip8
{
	// emulator
	var thread:Thread;
	var active:Bool = false;
	var drawFlag:Bool = true;
	public var starts:Int = 0;
	var lastTime:Float = 0;
	public var sps:Int = 0;
	var spc:Int = 0;
	var spsTime:Float = 0;
	public var beep:Bool = false;
	public var sleep:Float = 0.016;
	var timerTime:Float = 0;
	
	// cpu
	public var opcode:UInt = 0;
	public var I:UInt = 0;
	public var pc:UInt = 0;
	public var memory:ByteArray;
	public var V:ByteArray;
	public var gfx:ByteArray;
	public var delay_timer:UInt = 0;
	public var sound_timer:UInt = 0;
	public var key:ByteArray;
	public var sp:UInt = 0;
	public var stack:Array<UInt>;
	
	public function new() 
	{
		memory = new ByteArray();
		V = new ByteArray();
		gfx = new ByteArray();
		for (i in 0...2048) gfx.writeByte(0x00);
		key = new ByteArray();
		for (i in 0...16) key.writeByte(0x00);
		stack = new Array<UInt>();
		for (i in 0...16) stack.push(0);
		reset();
	}
	
	public function reset()
	{
		active = false;
		opcode = 0x0000;
		// reset index and program counter
		I = 0;
		pc = 0x200;
		// reset memory
		memory.clear();
		for (i in 0...4096) memory.writeByte(0x00);
		// reset registers
		V.clear();
		for (i in 0...16) V.writeByte(0x00);
		// clear screen
		clearScreen();
		// timers
		delay_timer = 0;
		sound_timer = 0;
		// keys
		for (i in 0...16) key[i] == 0x00;
		// stack
		sp = 0;
		for (i in 0...16) stack[i] = 0;
	}
	
	public function load(filename:String, fontsetFilename:String = "FONTSET")
	{
		active = false;
		reset();
		
		var fontset:ByteArray = Assets.getBytes("data/" + fontsetFilename);
		var program:ByteArray = Assets.getBytes("roms/" + filename);
		
		memoryInject(fontset, 0);
		memoryInject(program, 0x200);
	}
	
	public function memoryInject(data:ByteArray, offset:Int = 0, length:Int = 0)
	{
		if (length == 0) length = data.length;
		for (i in 0...length) memory[offset + i] = data[i]; 
	}
	
	public function clearScreen()
	{
		for (i in 0...(64 * 32)) gfx[i] = 0x00;
		drawFlag = true;
	}
	
	public function render(screen:BitmapData)
	{
		if (!drawFlag) return;
		
		drawFlag = false;
		
		var x:Int = 0;
		var y:Int = 0;
		gfx.position = 0;
		while (gfx.position < gfx.length) {
			if (gfx.readByte() > 0) {
				screen.setPixel(x, y, 0xFFFFFF);
			} else {
				screen.setPixel(x, y, 0x222222);
			}
			if (++x == 64) {
				y++;
				x = 0;
			}
		}
	}
	
	public function start()
	{
		if (!active) {
			active = true;
			thread = Thread.create(step);
		}
	}
	
	public function stop()
	{
		active = false;
	}
	
	public function step()
	{
		starts++;
		timerTime = spsTime = lastTime = Timer.stamp();
		
		while (active) {
			// fetch opcode
			opcode = memory[pc] << 8 | memory[pc + 1];
		
			// decode and execute opcode
			execute();
			
			// timers
			var stamp:Float = Timer.stamp();
			
			if (stamp - timerTime > 0.016) {
				timerTime = stamp;
				if(delay_timer > 0)
					--delay_timer;
					
				if (sound_timer > 0)
				{
					if (sound_timer == 1) beep = true;
					--sound_timer;
				}
			}
			
			// step counter
			spc++;
			if (stamp - spsTime > 1) {
				spsTime = stamp;
				sps = spc;
				spc = 0;
			}
			
			// delay
			//var time:Float = stamp - lastTime;
			//lastTime = stamp;
			Sys.sleep(sleep);
		}
	}
	
	public function execute()
	{
		if (pc >= memory.length) 
		{
			endOfProgram();
			return;
		}
		
		if (opcode == 0x0000) {
			pc += 2;
			return;
		}
		
		switch(opcode & 0xF000)
		{    
			case 0x0000: // special opcodes
			{
				switch (opcode & 0x000F)
				{
					case 0x0000: // 0x00E0: Clears the screen 
					{
						clearScreen();
						pc += 2;
					}
					case 0x000E: // 0x00EE: Returns from subroutine  
					{
						--sp;
						pc = stack[sp];
						pc += 2;
					}
					default:
						unknownOpcode();
				}
			}
			
			case 0x1000: // 1NNN: Jumps to address NNN
			{
				pc = opcode & 0x0FFF;
			}
			
			case 0x2000: // 2NNN: Calls subroutine at NNN.
			{
				stack[sp] = pc;
				++sp;
				pc = opcode & 0x0FFF;
			}
			
			case 0x3000: // 3XKK: Skip next instruction if Vx = kk.
			{
				if(V[(opcode & 0x0F00) >> 8] == (opcode & 0x00FF))
					pc += 4;
				else
					pc += 2;
			}
			
			case 0x4000: // 4XKK: Skip next instruction if Vx != kk.
			{
				if(V[(opcode & 0x0F00) >> 8] != (opcode & 0x00FF))
					pc += 4;
				else
					pc += 2;
			}
			
			case 0x5000: // 5XY0: Skip next instruction if Vx = Vy.
			{
				if (V[(opcode & 0x0F00) >> 8] == V[(opcode & 0x00F0) >> 4])
					pc += 4;
				else 
					pc += 2;
			}
			
			case 0x6000: // 6XKK: Set Vx = kk.
			{
				V[(opcode & 0x0F00) >> 8] = opcode & 0x00FF;
				pc += 2;
			}
			
			case 0x7000: // 7XKK: Set Vx = Vx + kk.
			{
				V[(opcode & 0x0F00) >> 8] = V[(opcode & 0x0F00) >> 8] + (opcode & 0x00FF);
				pc += 2;
			}
			
			case 0x8000: // Registers subset
			{
				switch (opcode & 0x000F)
				{
					case 0x0000: // 8XY0: Set Vx = Vy.
					{
						V[(opcode & 0x0F00) >> 8] = V[(opcode & 0x00F0) >> 4];
						pc += 2;
					}
					
					case 0x0001: // 8XY1: Set Vx = Vx OR Vy.
					{
						V[(opcode & 0x0F00) >> 8] = V[(opcode & 0x0F00) >> 8] | V[(opcode & 0x00F0) >> 4];
						pc += 2;
					}
					
					case 0x0002: // 8XY2: Set Vx = Vx AND Vy.
					{
						V[(opcode & 0x0F00) >> 8] = V[(opcode & 0x0F00) >> 8] & V[(opcode & 0x00F0) >> 4];
						pc += 2;
					}
					
					case 0x0003: // 8XY3: Set Vx = Vx XOR Vy.
					{
						V[(opcode & 0x0F00) >> 8] = V[(opcode & 0x0F00) >> 8] ^ V[(opcode & 0x00F0) >> 4];
						pc += 2;
					}
					
					case 0x0004: // 8XY4: Set Vx = Vx + Vy, set VF = carry.
					{
						if (V[(opcode & 0x00F0) >> 4] > (0xFF - V[(opcode & 0x0F00) >> 8])) 
							V[0xF] = 1; //carry
						else 
							V[0xF] = 0;					
						V[(opcode & 0x0F00) >> 8] = V[(opcode & 0x0F00) >> 8] + V[(opcode & 0x00F0) >> 4];
						pc += 2;
					}
					
					case 0x0005: // 8XY5: Set Vx = Vx - Vy, set VF = NOT borrow.
					{
						if(V[(opcode & 0x00F0) >> 4] > V[(opcode & 0x0F00) >> 8]) 
							V[0xF] = 0; // there is a borrow
						else 
							V[0xF] = 1;					
						V[(opcode & 0x0F00) >> 8] = V[(opcode & 0x0F00) >> 8] - V[(opcode & 0x00F0) >> 4];
						pc += 2;
					}
					
					case 0x0006: // 8XY6: Set Vx = Vx SHR 1.
					{
						V[0xF] = V[(opcode & 0x0F00) >> 8] & 0x1;
						V[(opcode & 0x0F00) >> 8] = V[(opcode & 0x0F00) >> 8] >> 1;
						pc += 2;
					}
					
					case 0x0007: // 8XY7: Set Vx = Vy - Vx, set VF = NOT borrow.
					{
						if(V[(opcode & 0x0F00) >> 8] > V[(opcode & 0x00F0) >> 4]) 
							V[0xF] = 0; // there is a borrow
						else 
							V[0xF] = 1;
						V[(opcode & 0x0F00) >> 8] = V[(opcode & 0x00F0) >> 4] - V[(opcode & 0x0F00) >> 8];
						pc += 2;
					}
					
					case 0x000E: // 8XYE: Set Vx = Vx SHL 1.
					{
						V[0xF] = V[(opcode & 0x0F00) >> 8] >> 7;
						V[(opcode & 0x0F00) >> 8] = V[(opcode & 0x0F00) >> 8] << 1;
						pc += 2;
					}
					
					default:
						unknownOpcode();
				}
			}
			
			case 0x9000: // 9XY0: Skip next instruction if Vx != Vy.
			{
				if (V[(opcode & 0x0F00) >> 8] != V[(opcode & 0x00F0) >> 4]) 
					pc += 4;
				else
					pc += 2;
			}
			
			case 0xA000: // ANNN: Sets I to the address NNN
			{	
				I = opcode & 0x0FFF;
				pc += 2;
			}
			
			case 0xB000: // BNNN: Jump to location nnn + V0.
			{
				pc = (opcode & 0x0FFF) + V[0];
			}
			
			case 0xC000: // CXKK: Set Vx = random byte AND kk.
			{
				V[(opcode & 0x0F00) >> 8] = Math.round(Math.random() * 0xFF) & (opcode & 0x00FF);
				pc += 2;
			}
			
			case 0xD000: // DXYN: Display n-byte sprite starting at memory location I at (Vx, Vy), set VF = collision.
			{
				drawSprite();
			}
			
			case 0xE000: // key input
			{
				switch (opcode & 0x00FF)
				{
					case 0x009E: // EX9E: Skip next instruction if key with the value of Vx is pressed.
					{
						if (key[V[(opcode & 0x0F00) >> 8]] != 0)
							pc += 4;
						else
							pc += 2;
					}
					
					case 0x00A1: // EXA1: Skip next instruction if key with the value of Vx is not pressed.
					{
						if (key[V[(opcode & 0x0F00) >> 8]] == 0)
							pc += 4;
						else
							pc += 2;
					}
					
					default:
						unknownOpcode();
				}
			}
			
			case 0xF000: // ???
			{
				switch (opcode & 0x00FF) {
					case 0x0007: // FX07: Set Vx = delay timer value.
					{
						V[(opcode & 0x0F00) >> 8] = delay_timer;
						pc += 2;
					}
					
					case 0x000A: // FX0A: Wait for a key press, store the value of the key in Vx.
					{
						var keyPressed:Bool = false;
						
						for (i in 0...16)
						{
							if (key[i] != 0) {
								V[(opcode & 0x0F00) >> 8] = i;
								keyPressed = true;
							}
						}
						
						if (!keyPressed)
							return;
							
						pc += 2;
					}
					
					case 0x0015: // FX15: Set delay timer = Vx.
					{
						delay_timer = V[(opcode & 0x0F00) >> 8];
						pc += 2;
					}
					
					case 0x0018: // FX18: Set sound timer = Vx.
					{
						sound_timer = V[(opcode & 0x0F00) >> 8];
						pc += 2;
					}
					
					case 0x001E: // FX1E: Set I = I + Vx.
					{
						if(I + V[(opcode & 0x0F00) >> 8] > 0xFFF)	// VF is set to 1 when range overflow (I+VX>0xFFF), and 0 when there isn't.
							V[0xF] = 1;
						else
							V[0xF] = 0;
						I += V[(opcode & 0x0F00) >> 8];
						if (I > 0xFFF) I -= 0xFFF; // there is no short so we have to do this shit
						pc += 2;
					}
					
					case 0x0029: // Fx29: Set I = location of sprite for digit Vx.
					{
						I = V[(opcode & 0x0F00) >> 8] * 0x5;
						pc += 2;
					}
					
					case 0x0033: // Fx33: Store BCD representation of Vx in memory locations I, I+1, and I+2.
					{
						memory[I]     = Math.floor(V[(opcode & 0x0F00) >> 8] / 100);
						memory[I + 1] = Math.floor(V[(opcode & 0x0F00) >> 8] / 10) % 10;
						memory[I + 2] = 		  (V[(opcode & 0x0F00) >> 8] % 100) % 10;
						
						pc += 2;
					}
					
					case 0x0055: // FX55: Store registers V0 through Vx in memory starting at location I.
					{
						for (i in 0...((opcode & 0x0F00) >> 8) + 1) {
							memory[I + i] = V[i];
						}
						I += V[(opcode & 0x0F00) >> 8] + 1;
						pc += 2;
					}
					
					case 0x0065: // FX65: Read registers V0 through Vx from memory starting at location I.
					{
						for (i in 0...((opcode & 0x0F00) >> 8) + 1) {
							V[i] = memory[I + i];
						}
						I += ((opcode & 0x0F00) >> 8) + 1;
						pc += 2;
					}
					
					default: 
						unknownOpcode();
				}
			}
				
			default:
				unknownOpcode();
		}  
	}
	
	public function drawSprite()
	{
		var x:UInt = V[(opcode & 0x0F00) >> 8];
		var y:UInt = V[(opcode & 0x00F0) >> 4];
		var height:UInt = opcode & 0x000F;
		var pixel:UInt = 0;

		V[0xF] = 0;
		for (yline in 0...height)
		{
			pixel = memory[I + yline];
			for(xline in 0...8)
			{
				if((pixel & (0x80 >> xline)) != 0)
				{
					if(gfx[(x + xline + ((y + yline) * 64))] == 1)
					{
						V[0xF] = 1;                                    
					}
					gfx[x + xline + ((y + yline) * 64)] = gfx[x + xline + ((y + yline) * 64)] ^ 1;
				}
			}
		}
					
		drawFlag = true;			
		pc += 2;
	}
	
	public function endOfProgram()
	{
		trace("Program ended");
		active = false;
	}
	
	public function unknownOpcode()
	{
		//trace("Unknown opcode: " + StringTools.hex(opcode));
		pc += 2;
	}
	
}