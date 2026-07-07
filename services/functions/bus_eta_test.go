package main

import "testing"

func TestPickBusEstimate(t *testing.T) {
	tests := []struct {
		name string
		prev rawBusEsimated
		next rawBusEsimated
		want rawBusEsimated
	}{
		{
			name: "status 0 beats status 1",
			prev: rawBusEsimated{StopStatus: 1, EstimatedTime: 10},
			next: rawBusEsimated{StopStatus: 0, EstimatedTime: 300},
			want: rawBusEsimated{StopStatus: 0, EstimatedTime: 300},
		},
		{
			name: "existing status 0 kept over incoming status 1",
			prev: rawBusEsimated{StopStatus: 0, EstimatedTime: 120},
			next: rawBusEsimated{StopStatus: 1, EstimatedTime: 5},
			want: rawBusEsimated{StopStatus: 0, EstimatedTime: 120},
		},
		{
			name: "smaller estimate wins among status 0",
			prev: rawBusEsimated{StopStatus: 0, EstimatedTime: 300},
			next: rawBusEsimated{StopStatus: 0, EstimatedTime: 60},
			want: rawBusEsimated{StopStatus: 0, EstimatedTime: 60},
		},
		{
			name: "larger estimate rejected among status 0",
			prev: rawBusEsimated{StopStatus: 0, EstimatedTime: 60},
			next: rawBusEsimated{StopStatus: 0, EstimatedTime: 300},
			want: rawBusEsimated{StopStatus: 0, EstimatedTime: 60},
		},
		{
			name: "first seen kept when all non-zero",
			prev: rawBusEsimated{StopStatus: 1, EstimatedTime: 200},
			next: rawBusEsimated{StopStatus: 1, EstimatedTime: 5},
			want: rawBusEsimated{StopStatus: 1, EstimatedTime: 200},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := pickBusEstimate(tt.prev, tt.next)
			if got != tt.want {
				t.Fatalf("pickBusEstimate() = %+v, want %+v", got, tt.want)
			}
		})
	}
}
